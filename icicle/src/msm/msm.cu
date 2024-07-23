#include "msm/msm.cuh"

#include <cooperative_groups.h>
#include <cub/device/device_radix_sort.cuh>
#include <cub/device/device_run_length_encode.cuh>
#include <cub/device/device_scan.cuh>
#include <cuda.h>

#include <iostream>
#include <stdexcept>
#include <vector>

#include "curves/affine.cuh"
#include "curves/projective.cuh"
#include "fields/field.cuh"
#include "gpu-utils/error_handler.cuh"
#include "utils/mont.cuh"


namespace msm {

  namespace {

#define MAX_TH 256

    // #define SSM_SUM  //WIP

    template <typename A, typename P>
    __global__ void left_shift_kernel(A* points, const unsigned shift, const unsigned count, A* points_out)
    {
      const unsigned tid = blockIdx.x * blockDim.x + threadIdx.x;
      if (tid >= count) return;
      P point = P::from_affine(points[tid]);
      for (unsigned i = 0; i < shift; i++)
        point = P::dbl(point);
      points_out[tid] = P::to_affine(point);
    }

    unsigned get_optimal_c(int msm_size) { return (unsigned)min(max(ceil(std::log2(msm_size)) - 4.0, 1.0), 22.0); }


    template <typename E>
    __global__ void normalize_kernel(E* inout, E factor, int n)
    {
      int tid = blockIdx.x * blockDim.x + threadIdx.x;
      if (tid < n) inout[tid] = (inout[tid] + factor - 1) / factor;
    }

    // a kernel that writes to bucket_indices which enables large bucket accumulation to happen afterwards.
    // specifically we map thread indices to buckets which said threads will handle in accumulation.
    template <typename P>
    __global__ void initialize_large_bucket_indices(
      unsigned* sorted_bucket_sizes_sum,
      unsigned nof_pts_per_thread,
      unsigned nof_large_buckets,
      // log_nof_buckets_to_compute should be equal to ceil(log(nof_buckets_to_compute))
      unsigned log_nof_large_buckets,
      unsigned* bucket_indices)
    {
      const int tid = blockIdx.x * blockDim.x + threadIdx.x;
      if (tid >= nof_large_buckets) { return; }
      unsigned start = (sorted_bucket_sizes_sum[tid] + nof_pts_per_thread - 1) / nof_pts_per_thread + tid;
      unsigned end = (sorted_bucket_sizes_sum[tid + 1] + nof_pts_per_thread - 1) / nof_pts_per_thread + tid + 1;
      for (unsigned i = start; i < end; i++) {
        // this just concatenates two pieces of data - large bucket index and (i - start)
        bucket_indices[i] = tid | ((i - start) << log_nof_large_buckets);
      }
    }

    // this function provides a single step of reduction across buckets sizes of
    // which are given by large_bucket_sizes pointer
    template <typename P>
    __global__ void sum_reduction_variable_size_kernel(
      P* v,
      unsigned* bucket_sizes_sum,
      unsigned* bucket_sizes,
      unsigned* large_bucket_thread_indices,
      unsigned nof_threads)
    {
      const int tid = blockIdx.x * blockDim.x + threadIdx.x;
      if (tid >= nof_threads) { return; }

      unsigned large_bucket_tid = large_bucket_thread_indices[tid];
      unsigned segment_ind = tid - bucket_sizes_sum[large_bucket_tid] - large_bucket_tid;
      unsigned large_bucket_size = bucket_sizes[large_bucket_tid];
      if (segment_ind < (large_bucket_size >> 1)) { v[tid] = v[tid] + v[tid + ((large_bucket_size + 1) >> 1)]; }
    }

    template <typename P>
    __global__ void single_stage_multi_reduction_kernel(
      const P* v,
      P* v_r,
      unsigned block_size,
      unsigned write_stride,
      unsigned buckets_per_bm,
      unsigned write_phase,
      unsigned step,
      unsigned nof_threads)
    {
      const int tid = blockIdx.x * blockDim.x + threadIdx.x;
      if (tid >= nof_threads) return;

      // we need shifted tid because we don't want to be reducing into zero buckets, this allows to skip them.
      // for write_phase==1, the read pattern is different so we don't skip over anything.
      const int shifted_tid = write_phase ? tid : tid + (tid + step) / step;
      const int jump = block_size / 2;
      const int block_id = shifted_tid / jump;
      // here the reason for shifting is the same as for shifted_tid but we skip over entire blocks which happens
      // only for write_phase=1 because of its read pattern.
      const int shifted_block_id = write_phase ? block_id + (block_id + step) / step : block_id;
      const int block_tid = shifted_tid % jump;
      const unsigned read_ind = block_size * shifted_block_id + block_tid;
      const unsigned write_ind = jump * shifted_block_id + block_tid;
      const unsigned v_r_key =
        write_stride ? ((write_ind / buckets_per_bm) * 2 + write_phase) * write_stride + write_ind % buckets_per_bm
                     : write_ind;
      v_r[v_r_key] = v[read_ind] + v[read_ind + jump];
    }

    // this kernel performs single scalar multiplication
    // each thread multiplies a single scalar and point
    template <typename P, typename S>
    __global__ void ssm_kernel(const S* scalars, const P* points, P* results, unsigned N)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid < N) results[tid] = scalars[tid] * points[tid];
    }

    // this kernel sums all the elements in a given vector using multiple threads
    template <typename P>
    __global__ void sum_reduction_kernel(P* v, P* v_r)
    {
      unsigned tid = blockIdx.x * blockDim.x + threadIdx.x;

      // Start at 1/2 block stride and divide by two each iteration
      for (unsigned s = blockDim.x / 2; s > 0; s >>= 1) {
        // Each thread does work unless it is further than the stride
        if (threadIdx.x < s) { v[tid] = v[tid] + v[tid + s]; }
        __syncthreads();
      }

      // Let the thread 0 for this block write the final result
      if (threadIdx.x == 0) { v_r[blockIdx.x] = v[tid]; }
    }

    // this kernel initializes the buckets with zero points
    // each thread initializes a different bucket
    template <typename P>
    __global__ void initialize_buckets_kernel(P* buckets, unsigned N)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid < N) buckets[tid] = P::zero(); // zero point
    }

    // this kernel splits the scalars into digits of size c
    // each thread splits a single scalar into nof_bms digits
    template <typename S>
    __global__ void split_scalars_kernel(
      unsigned* buckets_indices,
      unsigned* point_indices,
      const S* scalars,
      unsigned nof_scalars,
      unsigned points_size,
      unsigned msm_size,
      unsigned nof_bms,
      unsigned bm_bitsize,
      unsigned c,
      unsigned precomputed_bms_stride)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_scalars) return;

      unsigned bucket_index;
      unsigned current_index;
      unsigned msm_index = tid / msm_size;
      const S& scalar = scalars[tid];
      for (unsigned bm = 0; bm < nof_bms; bm++) {
        const unsigned precomputed_index = bm / precomputed_bms_stride;
        const unsigned target_bm = bm % precomputed_bms_stride;

        bucket_index = scalar.get_scalar_digit(bm, c);
        current_index = bm * nof_scalars + tid;

        if (bucket_index != 0) {
          buckets_indices[current_index] =
            (msm_index << (c + bm_bitsize)) | (target_bm << c) |
            bucket_index; // the bucket module number and the msm number are appended at the msbs
        } else {
          buckets_indices[current_index] = 0; // will be skipped
        }
        point_indices[current_index] =
          tid % points_size + points_size * precomputed_index; // the point index is saved for later
      }
    }

    template <typename S>
    __global__ void
    find_cutoff_kernel(unsigned* v, unsigned size, unsigned cutoff, unsigned run_length, unsigned* result)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      const unsigned nof_threads = (size + run_length - 1) / run_length;
      if (tid >= nof_threads) { return; }
      const unsigned start_index = tid * run_length;
      for (int i = start_index; i < min(start_index + run_length, size - 1); i++) {
        if (v[i] > cutoff && v[i + 1] <= cutoff) {
          result[0] = i + 1;
          return;
        }
      }
      if (tid == 0 && v[size - 1] > cutoff) { result[0] = size; }
    }

    // this kernel adds up the points in each bucket
    template <typename P, typename A>
    __global__ void accumulate_buckets_kernel(
      P* __restrict__ buckets,
      unsigned* __restrict__ bucket_offsets,
      unsigned* __restrict__ bucket_sizes,
      unsigned* __restrict__ single_bucket_indices,
      const unsigned* __restrict__ point_indices,
      A* __restrict__ points,
      const unsigned nof_buckets,
      const unsigned nof_buckets_to_compute,
      const unsigned msm_idx_shift,
      const unsigned c,
      bool init_buckets)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_buckets_to_compute) return;
      unsigned msm_index = single_bucket_indices[tid] >> msm_idx_shift;
      const unsigned single_bucket_index = (single_bucket_indices[tid] & ((1 << msm_idx_shift) - 1));
      unsigned bucket_index = msm_index * nof_buckets + single_bucket_index;
      const unsigned bucket_offset = bucket_offsets[tid];
      const unsigned bucket_size = bucket_sizes[tid];

      P bucket; // get rid of init buckets? no.. because what about buckets with no points
      if (!init_buckets) bucket = buckets[bucket_index];
      for (unsigned i = 0; i < bucket_size;
           i++) { // add the relevant points starting from the relevant offset up to the bucket size
        unsigned point_ind = point_indices[bucket_offset + i];
        A point = points[point_ind];
        bucket =
          i || !init_buckets ? (point == A::zero() ? bucket : bucket + point) : (point == A::zero() ? P::zero() : P::from_affine(point));
      }
      buckets[bucket_index] = bucket;
    }

    template <typename P, typename A>
    __global__ void accumulate_large_buckets_kernel(
      P* __restrict__ buckets,
      unsigned* __restrict__ bucket_offsets,
      unsigned* __restrict__ bucket_sizes,
      unsigned* __restrict__ large_bucket_thread_indices,
      unsigned* __restrict__ point_indices,
      A* __restrict__ points,
      const unsigned nof_buckets_to_compute,
      const unsigned c,
      const int points_per_thread,
      // log_nof_buckets_to_compute should be equal to ceil(log(nof_buckets_to_compute))
      const unsigned log_nof_buckets_to_compute,
      const unsigned nof_threads)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_threads) return;
      int bucket_segment_index = large_bucket_thread_indices[tid] >> log_nof_buckets_to_compute;
      large_bucket_thread_indices[tid] &= ((1 << log_nof_buckets_to_compute) - 1);
      int bucket_ind = large_bucket_thread_indices[tid];
      const unsigned bucket_offset = bucket_offsets[bucket_ind] + bucket_segment_index * points_per_thread;
      const unsigned bucket_size = max(0, (int)bucket_sizes[bucket_ind] - bucket_segment_index * points_per_thread);
      P bucket;
      unsigned run_length = min(bucket_size, points_per_thread);
      for (unsigned i = 0; i < run_length;
           i++) { // add the relevant points starting from the relevant offset up to the bucket size
        unsigned point_ind = point_indices[bucket_offset + i];
        A point = points[point_ind];
        bucket =
          i ? (point == A::zero() ? bucket : bucket + point) : (point == A::zero() ? P::zero() : P::from_affine(point));
      }
      buckets[tid] = run_length ? bucket : P::zero();
    }

    template <typename P>
    __global__ void distribute_large_buckets_kernel(
      const P* large_buckets,
      P* buckets,
      const unsigned* sorted_bucket_sizes_sum,
      const unsigned* single_bucket_indices,
      const unsigned size,
      const unsigned nof_buckets,
      const unsigned msm_idx_shift,
      bool init_buckets)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= size) { return; }

      unsigned msm_index = single_bucket_indices[tid] >> msm_idx_shift;
      unsigned bucket_index = msm_index * nof_buckets + (single_bucket_indices[tid] & ((1 << msm_idx_shift) - 1));
      unsigned large_bucket_index = sorted_bucket_sizes_sum[tid] + tid;
      buckets[bucket_index] = init_buckets ? large_buckets[large_bucket_index] : buckets[bucket_index] + large_buckets[large_bucket_index];
      // buckets[bucket_index] = large_buckets[large_bucket_index];
    }

    // this kernel sums the entire bucket module
    // each thread deals with a single bucket module
    template <typename P>
    __global__ void big_triangle_sum_kernel(const P* buckets, P* final_sums, unsigned nof_bms, unsigned c)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_bms) return;
      unsigned buckets_in_bm = (1 << c);
      P line_sum = buckets[(tid + 1) * buckets_in_bm - 1];
      final_sums[tid] = line_sum;
      for (unsigned i = buckets_in_bm - 2; i > 0; i--) {
        line_sum = line_sum + buckets[tid * buckets_in_bm + i]; // using the running sum method
        final_sums[tid] = final_sums[tid] + line_sum;
      }
    }

    // this kernel uses single scalar multiplication to multiply each bucket by its index
    // each thread deals with a single bucket
    template <typename P, typename S>
    __global__ void ssm_buckets_kernel(P* buckets, unsigned* single_bucket_indices, unsigned nof_buckets, unsigned c)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_buckets) return;
      unsigned bucket_index = single_bucket_indices[tid];
      S scalar_bucket_multiplier;
      scalar_bucket_multiplier = {
        bucket_index & ((1 << c) - 1), 0, 0, 0, 0, 0, 0, 0}; // the index without the bucket module index
      buckets[bucket_index] = scalar_bucket_multiplier * buckets[bucket_index];
    }

    template <typename P>
    __global__ void last_pass_kernel(
      const P* final_buckets,
      P* final_sums,
      unsigned nof_sums_per_batch,
      unsigned batch_size,
      unsigned nof_bms_per_batch,
      unsigned orig_c)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_sums_per_batch * batch_size) return;
      unsigned batch_index = tid / nof_sums_per_batch;
      unsigned batch_tid = tid % nof_sums_per_batch;
      unsigned bm_index = batch_tid / orig_c;
      unsigned bm_tid = batch_tid % orig_c;
      for (unsigned c = orig_c; c > 1;) {
        c = (c + 1) >> 1;
        bm_index <<= 1;
        if (bm_tid >= c) {
          bm_index++;
          bm_tid -= c;
        }
      }
      final_sums[tid] = final_buckets[2 * (batch_index * nof_bms_per_batch + bm_index) + 1];
    }

    // this kernel computes the final result using the double and add algorithm
    // it is done by a single thread
    template <typename P, typename S>
    __global__ void final_accumulation_kernel(
      const P* final_sums, P* final_results, unsigned nof_msms, unsigned nof_results, unsigned c)
    {
      unsigned tid = (blockIdx.x * blockDim.x) + threadIdx.x;
      if (tid >= nof_msms) return;
      P final_result = P::zero();
      // Note: in some cases accumulation of bm is implemented such that some bms are known to be empty. Therefore
      // skipping them.
      for (unsigned i = nof_results; i > 1; i--) {
        final_result = final_result + final_sums[i - 1 + tid * nof_results]; // add
        for (unsigned j = 0; j < c; j++)                                     // double
        {
          final_result = final_result + final_result;
        }
      }
      final_results[tid] = final_result + final_sums[tid * nof_results];
    }

    // this function computes msm using the bucket method
    template <typename S, typename P, typename A>
    cudaError_t bucket_method_msm(
      unsigned bitsize,
      unsigned c,
      const S* scalars,
      const A* points,
      A** points_processed,
      bool return_processed_points,
      bool init_points,
      unsigned batch_size,      // number of MSMs to compute
      unsigned single_msm_size, // number of elements per MSM (a.k.a N)
      bool are_points_shared_in_batch,      // number of EC points in 'points' array. Must be either (1) single_msm_size if MSMs are
                                // sharing points or (2) single_msm_size*batch_size otherwise
      P** buckets_external,
      bool init_buckets,
      bool return_buckets,
      P* final_result,
      bool are_scalars_on_device,
      bool are_scalars_montgomery_form,
      bool are_points_on_device,
      bool are_points_montgomery_form,
      bool are_results_on_device,
      bool is_big_triangle,
      int large_bucket_factor,
      int precompute_factor,
      bool is_async,
      cudaStream_t stream)
    {
      CHK_INIT_IF_RETURN();

      const unsigned nof_scalars = batch_size * single_msm_size; // assuming scalars not shared between batch elements
      unsigned nof_points = are_points_shared_in_batch? single_msm_size : nof_scalars;
        // printf("single_msm_size %d nof_points %d\n", single_msm_size, nof_points);

      const S* d_scalars;
      S* d_allocated_scalars = nullptr;
      if (!are_scalars_on_device) {
        // copy scalars to gpu
        CHK_IF_RETURN(cudaMallocAsync(&d_allocated_scalars, sizeof(S) * nof_scalars, stream));
        CHK_IF_RETURN(
          cudaMemcpyAsync(d_allocated_scalars, scalars, sizeof(S) * nof_scalars, cudaMemcpyHostToDevice, stream));

        if (are_scalars_montgomery_form) {
          CHK_IF_RETURN(mont::from_montgomery(d_allocated_scalars, nof_scalars, stream, d_allocated_scalars));
        }
        d_scalars = d_allocated_scalars;
      } else { // already on device
        if (are_scalars_montgomery_form) {
          CHK_IF_RETURN(cudaMallocAsync(&d_allocated_scalars, sizeof(S) * nof_scalars, stream));
          CHK_IF_RETURN(mont::from_montgomery(scalars, nof_scalars, stream, d_allocated_scalars));
          d_scalars = d_allocated_scalars;
        } else {
          d_scalars = scalars;
        }
      }

      unsigned total_bms_per_msm = (bitsize + c - 1) / c;
      unsigned nof_bms_per_msm = (total_bms_per_msm - 1) / precompute_factor + 1;
      unsigned input_indexes_count = nof_scalars * total_bms_per_msm;

      unsigned bm_bitsize = (unsigned)ceil(std::log2(nof_bms_per_msm));

      unsigned* bucket_indices;
      unsigned* point_indices;
      unsigned* sorted_bucket_indices;
      unsigned* sorted_point_indices;
      CHK_IF_RETURN(cudaMallocAsync(&bucket_indices, sizeof(unsigned) * input_indexes_count, stream));
      CHK_IF_RETURN(cudaMallocAsync(&point_indices, sizeof(unsigned) * input_indexes_count, stream));
      CHK_IF_RETURN(cudaMallocAsync(&sorted_bucket_indices, sizeof(unsigned) * input_indexes_count, stream));
      CHK_IF_RETURN(cudaMallocAsync(&sorted_point_indices, sizeof(unsigned) * input_indexes_count, stream));

      // split scalars into digits
      unsigned NUM_THREADS = 1 << 10;
      unsigned NUM_BLOCKS = (nof_scalars + NUM_THREADS - 1) / NUM_THREADS;

      split_scalars_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
        bucket_indices, point_indices, d_scalars, nof_scalars, nof_points, single_msm_size, total_bms_per_msm,
        bm_bitsize, c, nof_bms_per_msm);
      nof_points *= precompute_factor;

      // ------------------------------ Sorting routines for scalars start here ----------------------------------
      // sort indices - the indices are sorted from smallest to largest in order to group together the points that
      // belong to each bucket
      unsigned* sort_indices_temp_storage{};
      size_t sort_indices_temp_storage_bytes;
      // The second to last parameter is the default value supplied explicitly to allow passing the stream
      // See https://nvlabs.github.io/cub/structcub_1_1_device_radix_sort.html#a65e82152de448c6373ed9563aaf8af7e for
      // more info
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairs(
        sort_indices_temp_storage, sort_indices_temp_storage_bytes, bucket_indices, sorted_bucket_indices,
        point_indices, sorted_point_indices, input_indexes_count, 0, sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaMallocAsync(&sort_indices_temp_storage, sort_indices_temp_storage_bytes, stream));
      // The second to last parameter is the default value supplied explicitly to allow passing the stream
      // See https://nvlabs.github.io/cub/structcub_1_1_device_radix_sort.html#a65e82152de448c6373ed9563aaf8af7e for
      // more info
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairs(
        sort_indices_temp_storage, sort_indices_temp_storage_bytes, bucket_indices, sorted_bucket_indices,
        point_indices, sorted_point_indices, input_indexes_count, 0, sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaFreeAsync(sort_indices_temp_storage, stream));
      CHK_IF_RETURN(cudaFreeAsync(bucket_indices, stream));
      CHK_IF_RETURN(cudaFreeAsync(point_indices, stream));

      // compute number of bucket modules and number of buckets in each module
      unsigned nof_bms_in_batch = nof_bms_per_msm * batch_size;
      // minus nof_bms_per_msm because zero bucket is not included in each bucket module
      const unsigned nof_buckets = (nof_bms_per_msm << c) - nof_bms_per_msm;
      const unsigned total_nof_buckets = nof_buckets * batch_size;

      // find bucket_sizes
      unsigned* single_bucket_indices;
      unsigned* bucket_sizes;
      unsigned* nof_buckets_to_compute;
      // +1 here and in other places because there still is zero index corresponding to zero bucket at this point
      CHK_IF_RETURN(cudaMallocAsync(&single_bucket_indices, sizeof(unsigned) * (total_nof_buckets + 1), stream));
      CHK_IF_RETURN(cudaMallocAsync(&bucket_sizes, sizeof(unsigned) * (total_nof_buckets + 1), stream));
      CHK_IF_RETURN(cudaMallocAsync(&nof_buckets_to_compute, sizeof(unsigned), stream));
      unsigned* encode_temp_storage{};
      size_t encode_temp_storage_bytes = 0;
      CHK_IF_RETURN(cub::DeviceRunLengthEncode::Encode(
        encode_temp_storage, encode_temp_storage_bytes, sorted_bucket_indices, single_bucket_indices, bucket_sizes,
        nof_buckets_to_compute, input_indexes_count, stream));
      CHK_IF_RETURN(cudaMallocAsync(&encode_temp_storage, encode_temp_storage_bytes, stream));
      CHK_IF_RETURN(cub::DeviceRunLengthEncode::Encode(
        encode_temp_storage, encode_temp_storage_bytes, sorted_bucket_indices, single_bucket_indices, bucket_sizes,
        nof_buckets_to_compute, input_indexes_count, stream));
      CHK_IF_RETURN(cudaFreeAsync(encode_temp_storage, stream));
      CHK_IF_RETURN(cudaFreeAsync(sorted_bucket_indices, stream));

      // get offsets - where does each new bucket begin
      unsigned* bucket_offsets;
      CHK_IF_RETURN(cudaMallocAsync(&bucket_offsets, sizeof(unsigned) * (total_nof_buckets + 1), stream));
      unsigned* offsets_temp_storage{};
      size_t offsets_temp_storage_bytes = 0;
      CHK_IF_RETURN(cub::DeviceScan::ExclusiveSum(
        offsets_temp_storage, offsets_temp_storage_bytes, bucket_sizes, bucket_offsets, total_nof_buckets + 1, stream));
      CHK_IF_RETURN(cudaMallocAsync(&offsets_temp_storage, offsets_temp_storage_bytes, stream));
      CHK_IF_RETURN(cub::DeviceScan::ExclusiveSum(
        offsets_temp_storage, offsets_temp_storage_bytes, bucket_sizes, bucket_offsets, total_nof_buckets + 1, stream));
      CHK_IF_RETURN(cudaFreeAsync(offsets_temp_storage, stream));

      // ----------- Starting to upload points (if they were on host) in parallel to scalar sorting ----------------
      const A* d_points;
      A* d_allocated_points = nullptr;
      cudaStream_t stream_points = nullptr;
      if (init_points){
        if (!are_points_on_device || are_points_montgomery_form) CHK_IF_RETURN(cudaStreamCreate(&stream_points));
        if (!are_points_on_device) {
          // copy points to gpu
          CHK_IF_RETURN(cudaMallocAsync(&d_allocated_points, sizeof(A) * nof_points, stream_points));
          CHK_IF_RETURN(
            cudaMemcpyAsync(d_allocated_points, points, sizeof(A) * nof_points, cudaMemcpyHostToDevice, stream_points));

          if (are_points_montgomery_form) {
            CHK_IF_RETURN(mont::from_montgomery(d_allocated_points, nof_points, stream_points, d_allocated_points));
          }
          d_points = d_allocated_points;
        } else { // already on device
          if (are_points_montgomery_form) {
            CHK_IF_RETURN(cudaMallocAsync(&d_allocated_points, sizeof(A) * nof_points, stream_points));
            CHK_IF_RETURN(mont::from_montgomery(points, nof_points, stream_points, d_allocated_points));
            d_points = d_allocated_points;
          } else {
            d_points = points;
          }
        }
      }
      else{
        d_points = *points_processed;
      }
      if (return_processed_points) *points_processed = d_allocated_points; //return pointer to processed points for the next msm in batch

      cudaEvent_t event_points_uploaded;
      if (stream_points) {
        CHK_IF_RETURN(cudaEventCreateWithFlags(&event_points_uploaded, cudaEventDisableTiming));
        CHK_IF_RETURN(cudaEventRecord(event_points_uploaded, stream_points));
      }

      // printf("before init buckets\n");
      P* buckets;
      if (init_buckets){
        CHK_IF_RETURN(cudaMallocAsync(&buckets, sizeof(P) * (total_nof_buckets + nof_bms_in_batch), stream));
        
        // launch the bucket initialization kernel with maximum threads
        NUM_THREADS = 1 << 10;
        NUM_BLOCKS = (total_nof_buckets + nof_bms_in_batch + NUM_THREADS - 1) / NUM_THREADS;
        initialize_buckets_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(buckets, total_nof_buckets + nof_bms_in_batch);
        // printf("init buckets\n");
      }
      else{
        buckets = *buckets_external;
        // printf("assign buckets\n");
      }


      // removing zero bucket, if it exists
      unsigned smallest_bucket_index;
      CHK_IF_RETURN(cudaMemcpyAsync(
        &smallest_bucket_index, single_bucket_indices, sizeof(unsigned), cudaMemcpyDeviceToHost, stream));
      // maybe zero bucket is empty after all? in this case zero_bucket_offset is set to 0
      unsigned zero_bucket_offset = (smallest_bucket_index == 0) ? 1 : 0;

      // sort by bucket sizes
      unsigned h_nof_buckets_to_compute;
      CHK_IF_RETURN(cudaMemcpyAsync(
        &h_nof_buckets_to_compute, nof_buckets_to_compute, sizeof(unsigned), cudaMemcpyDeviceToHost, stream));
      CHK_IF_RETURN(cudaFreeAsync(nof_buckets_to_compute, stream));
      h_nof_buckets_to_compute -= zero_bucket_offset;

      unsigned* sorted_bucket_sizes;
      CHK_IF_RETURN(cudaMallocAsync(&sorted_bucket_sizes, sizeof(unsigned) * h_nof_buckets_to_compute, stream));
      unsigned* sorted_bucket_offsets;
      CHK_IF_RETURN(cudaMallocAsync(&sorted_bucket_offsets, sizeof(unsigned) * h_nof_buckets_to_compute, stream));
      unsigned* sort_offsets_temp_storage{};
      size_t sort_offsets_temp_storage_bytes = 0;
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairsDescending(
        sort_offsets_temp_storage, sort_offsets_temp_storage_bytes, bucket_sizes + zero_bucket_offset,
        sorted_bucket_sizes, bucket_offsets + zero_bucket_offset, sorted_bucket_offsets, h_nof_buckets_to_compute, 0,
        sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaMallocAsync(&sort_offsets_temp_storage, sort_offsets_temp_storage_bytes, stream));
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairsDescending(
        sort_offsets_temp_storage, sort_offsets_temp_storage_bytes, bucket_sizes + zero_bucket_offset,
        sorted_bucket_sizes, bucket_offsets + zero_bucket_offset, sorted_bucket_offsets, h_nof_buckets_to_compute, 0,
        sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaFreeAsync(sort_offsets_temp_storage, stream));
      CHK_IF_RETURN(cudaFreeAsync(bucket_offsets, stream));

      unsigned* sorted_single_bucket_indices;
      CHK_IF_RETURN(
        cudaMallocAsync(&sorted_single_bucket_indices, sizeof(unsigned) * h_nof_buckets_to_compute, stream));
      unsigned* sort_single_temp_storage{};
      size_t sort_single_temp_storage_bytes = 0;
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairsDescending(
        sort_single_temp_storage, sort_single_temp_storage_bytes, bucket_sizes + zero_bucket_offset,
        sorted_bucket_sizes, single_bucket_indices + zero_bucket_offset, sorted_single_bucket_indices,
        h_nof_buckets_to_compute, 0, sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaMallocAsync(&sort_single_temp_storage, sort_single_temp_storage_bytes, stream));
      CHK_IF_RETURN(cub::DeviceRadixSort::SortPairsDescending(
        sort_single_temp_storage, sort_single_temp_storage_bytes, bucket_sizes + zero_bucket_offset,
        sorted_bucket_sizes, single_bucket_indices + zero_bucket_offset, sorted_single_bucket_indices,
        h_nof_buckets_to_compute, 0, sizeof(unsigned) * 8, stream));
      CHK_IF_RETURN(cudaFreeAsync(sort_single_temp_storage, stream));
      CHK_IF_RETURN(cudaFreeAsync(bucket_sizes, stream));
      CHK_IF_RETURN(cudaFreeAsync(single_bucket_indices, stream));

      // find large buckets
      unsigned average_bucket_size = (single_msm_size / (1 << c)) * precompute_factor;
      // how large a bucket must be to qualify as a "large bucket"
      unsigned bucket_th = large_bucket_factor * average_bucket_size;
      unsigned* nof_large_buckets;
      CHK_IF_RETURN(cudaMallocAsync(&nof_large_buckets, sizeof(unsigned), stream));
      CHK_IF_RETURN(cudaMemset(nof_large_buckets, 0, sizeof(unsigned)));

      unsigned TOTAL_THREADS = 129000; // TODO: device dependent
      unsigned cutoff_run_length = max(2, h_nof_buckets_to_compute / TOTAL_THREADS);
      unsigned cutoff_nof_runs = (h_nof_buckets_to_compute + cutoff_run_length - 1) / cutoff_run_length;
      NUM_THREADS = 1 << 5;
      NUM_BLOCKS = (cutoff_nof_runs + NUM_THREADS - 1) / NUM_THREADS;
      if (h_nof_buckets_to_compute > 0 && bucket_th > 0)
        find_cutoff_kernel<S><<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
          sorted_bucket_sizes, h_nof_buckets_to_compute, bucket_th, cutoff_run_length, nof_large_buckets);
      unsigned h_nof_large_buckets;
      CHK_IF_RETURN(
        cudaMemcpyAsync(&h_nof_large_buckets, nof_large_buckets, sizeof(unsigned), cudaMemcpyDeviceToHost, stream));
      CHK_IF_RETURN(cudaFreeAsync(nof_large_buckets, stream));

      if (stream_points) {
        // by this point, points need to be already uploaded and un-Montgomeried
        CHK_IF_RETURN(cudaStreamWaitEvent(stream, event_points_uploaded));
        CHK_IF_RETURN(cudaEventDestroy(event_points_uploaded));
        CHK_IF_RETURN(cudaStreamDestroy(stream_points));
      }

      cudaStream_t stream_large_buckets;
      cudaEvent_t event_large_buckets_accumulated;
      // ---------------- This is where handling of large buckets happens (if there are any) -------------
      if (h_nof_large_buckets > 0 && bucket_th > 0) {
        CHK_IF_RETURN(cudaStreamCreate(&stream_large_buckets));
        CHK_IF_RETURN(cudaEventCreateWithFlags(&event_large_buckets_accumulated, cudaEventDisableTiming));

        unsigned* sorted_bucket_sizes_sum;
        CHK_IF_RETURN(cudaMallocAsync(
          &sorted_bucket_sizes_sum, sizeof(unsigned) * (h_nof_large_buckets + 1), stream_large_buckets));
        CHK_IF_RETURN(cudaMemsetAsync(sorted_bucket_sizes_sum, 0, sizeof(unsigned), stream_large_buckets));
        unsigned* large_bucket_temp_storage{};
        size_t large_bucket_temp_storage_bytes = 0;
        CHK_IF_RETURN(cub::DeviceScan::InclusiveSum(
          large_bucket_temp_storage, large_bucket_temp_storage_bytes, sorted_bucket_sizes, sorted_bucket_sizes_sum + 1,
          h_nof_large_buckets, stream_large_buckets));
        CHK_IF_RETURN(
          cudaMallocAsync(&large_bucket_temp_storage, large_bucket_temp_storage_bytes, stream_large_buckets));
        CHK_IF_RETURN(cub::DeviceScan::InclusiveSum(
          large_bucket_temp_storage, large_bucket_temp_storage_bytes, sorted_bucket_sizes, sorted_bucket_sizes_sum + 1,
          h_nof_large_buckets, stream_large_buckets));
        CHK_IF_RETURN(cudaFreeAsync(large_bucket_temp_storage, stream_large_buckets));
        unsigned h_nof_pts_in_large_buckets;
        CHK_IF_RETURN(cudaMemcpyAsync(
          &h_nof_pts_in_large_buckets, sorted_bucket_sizes_sum + h_nof_large_buckets, sizeof(unsigned),
          cudaMemcpyDeviceToHost, stream_large_buckets));
        unsigned h_largest_bucket;
        CHK_IF_RETURN(cudaMemcpyAsync(
          &h_largest_bucket, sorted_bucket_sizes, sizeof(unsigned), cudaMemcpyDeviceToHost, stream_large_buckets));

        // the number of threads for large buckets has an extra h_nof_large_buckets term to account for bucket sizes
        // unevenly divisible by average_bucket_size. there are similar corrections elsewhere when accessing large
        // buckets
        unsigned large_buckets_nof_threads =
          (h_nof_pts_in_large_buckets + average_bucket_size - 1) / average_bucket_size + h_nof_large_buckets;
        unsigned log_nof_large_buckets = (unsigned)ceil(std::log2(h_nof_large_buckets));
        unsigned* large_bucket_indices;
        CHK_IF_RETURN(cudaMallocAsync(&large_bucket_indices, sizeof(unsigned) * large_buckets_nof_threads, stream));
        NUM_THREADS = max(1, min(1 << 8, h_nof_large_buckets));
        NUM_BLOCKS = (h_nof_large_buckets + NUM_THREADS - 1) / NUM_THREADS;
        initialize_large_bucket_indices<P><<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
          sorted_bucket_sizes_sum, average_bucket_size, h_nof_large_buckets, log_nof_large_buckets,
          large_bucket_indices);

        P* large_buckets;
        CHK_IF_RETURN(cudaMallocAsync(&large_buckets, sizeof(P) * large_buckets_nof_threads, stream_large_buckets));

        NUM_THREADS = max(1, min(1 << 8, large_buckets_nof_threads));
        NUM_BLOCKS = (large_buckets_nof_threads + NUM_THREADS - 1) / NUM_THREADS;
        accumulate_large_buckets_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
          large_buckets, sorted_bucket_offsets, sorted_bucket_sizes, large_bucket_indices, sorted_point_indices,
          d_points, h_nof_large_buckets, c, average_bucket_size, log_nof_large_buckets, large_buckets_nof_threads);

        NUM_THREADS = max(1, min(MAX_TH, h_nof_large_buckets));
        NUM_BLOCKS = (h_nof_large_buckets + NUM_THREADS - 1) / NUM_THREADS;
        // normalization is needed to update buckets sizes and offsets due to reduction that already took place
        normalize_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
          sorted_bucket_sizes_sum, average_bucket_size, h_nof_large_buckets);
        // reduce
        for (int s = h_largest_bucket; s > 1; s = ((s + 1) >> 1)) {
          NUM_THREADS = max(1, min(MAX_TH, h_nof_large_buckets));
          NUM_BLOCKS = (h_nof_large_buckets + NUM_THREADS - 1) / NUM_THREADS;
          normalize_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
            sorted_bucket_sizes, s == h_largest_bucket ? average_bucket_size : 2, h_nof_large_buckets);
          NUM_THREADS = max(1, min(MAX_TH, large_buckets_nof_threads));
          NUM_BLOCKS = (large_buckets_nof_threads + NUM_THREADS - 1) / NUM_THREADS;
          sum_reduction_variable_size_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
            large_buckets, sorted_bucket_sizes_sum, sorted_bucket_sizes, large_bucket_indices,
            large_buckets_nof_threads);
        }
        CHK_IF_RETURN(cudaFreeAsync(large_bucket_indices, stream_large_buckets));
        // cudaDeviceSynchronize();
        // std::cout << "1 cuda err: " << cudaGetErrorString(cudaGetLastError()) << std::endl;

        // distribute
        NUM_THREADS = max(1, min(MAX_TH, h_nof_large_buckets));
        NUM_BLOCKS = (h_nof_large_buckets + NUM_THREADS - 1) / NUM_THREADS;
        distribute_large_buckets_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_large_buckets>>>(
          large_buckets, buckets, sorted_bucket_sizes_sum, sorted_single_bucket_indices, h_nof_large_buckets,
          nof_buckets + nof_bms_per_msm, c + bm_bitsize, init_buckets);
        // cudaDeviceSynchronize();
        // std::cout << "2 cuda err: " << cudaGetErrorString(cudaGetLastError()) << std::endl;
        CHK_IF_RETURN(cudaFreeAsync(large_buckets, stream_large_buckets));
        CHK_IF_RETURN(cudaFreeAsync(sorted_bucket_sizes_sum, stream_large_buckets));

        CHK_IF_RETURN(cudaEventRecord(event_large_buckets_accumulated, stream_large_buckets));
      }

  // printf("buckets pre acc:\n");
  // P* buckets_h = new P[8];
  // cudaMemcpy(buckets_h, buckets, sizeof(P) * 8, cudaMemcpyDeviceToHost);
  // for (int i = 0; i < 8; i++)
  // {
  //   std::cout << buckets_h[i] << "\n";
  // }

      // ------------------------- Accumulation of (non-large) buckets ---------------------------------
      if (h_nof_buckets_to_compute > h_nof_large_buckets) {
        NUM_THREADS = 1 << 8;
        NUM_BLOCKS = (h_nof_buckets_to_compute - h_nof_large_buckets + NUM_THREADS - 1) / NUM_THREADS;
        // launch the accumulation kernel with maximum threads
        accumulate_buckets_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
          buckets, sorted_bucket_offsets + h_nof_large_buckets, sorted_bucket_sizes + h_nof_large_buckets,
          sorted_single_bucket_indices + h_nof_large_buckets, sorted_point_indices, d_points,
          nof_buckets + nof_bms_per_msm, h_nof_buckets_to_compute - h_nof_large_buckets, c + bm_bitsize, c, init_buckets);
      }

  // printf("buckets post acc:\n");
  // // P* buckets_h = new P[8];
  // cudaMemcpy(buckets_h, buckets, sizeof(P) * 8, cudaMemcpyDeviceToHost);
  // for (int i = 0; i < 8; i++)
  // {
  //   std::cout << buckets_h[i] << "\n";
  // }


      CHK_IF_RETURN(cudaFreeAsync(sorted_point_indices, stream));
      CHK_IF_RETURN(cudaFreeAsync(sorted_bucket_sizes, stream));
      CHK_IF_RETURN(cudaFreeAsync(sorted_bucket_offsets, stream));
      CHK_IF_RETURN(cudaFreeAsync(sorted_single_bucket_indices, stream));
      if (h_nof_large_buckets > 0 && bucket_th > 0) {
        // all the large buckets need to be accumulated before the final summation
        CHK_IF_RETURN(cudaStreamWaitEvent(stream, event_large_buckets_accumulated));
        CHK_IF_RETURN(cudaStreamDestroy(stream_large_buckets));
      }


      if (return_buckets) {
        *buckets_external = buckets;
        return CHK_LAST();
      }


      P* d_allocated_final_result = nullptr;
      if (!are_results_on_device)
        CHK_IF_RETURN(cudaMallocAsync(&d_allocated_final_result, sizeof(P) * batch_size, stream));

      // --- Reduction of buckets happens here, after this we'll get a single sum for each bucket module/window ---
      unsigned nof_final_results_per_msm =
        nof_bms_per_msm; // for big-triangle accumluation this is the number of bucket modules
      P* final_results;
      if (is_big_triangle || c == 1) {
        CHK_IF_RETURN(cudaMallocAsync(&final_results, sizeof(P) * nof_bms_in_batch, stream));
        // launch the bucket module sum kernel - a thread for each bucket module
        NUM_THREADS = 32;
        NUM_BLOCKS = (nof_bms_in_batch + NUM_THREADS - 1) / NUM_THREADS;
        big_triangle_sum_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(buckets, final_results, nof_bms_in_batch, c);
      } else {
        // the recursive reduction algorithm works with 2 types of reduction that can run on parallel streams
        cudaStream_t stream_reduction;
        cudaEvent_t event_finished_reduction;
        CHK_IF_RETURN(cudaStreamCreate(&stream_reduction));
        CHK_IF_RETURN(cudaEventCreateWithFlags(&event_finished_reduction, cudaEventDisableTiming));

        unsigned source_bits_count = c;
        unsigned source_windows_count = nof_bms_per_msm;
        unsigned source_buckets_count = nof_buckets + nof_bms_per_msm; // nof buckets per msm including zero buckets
        unsigned target_windows_count;
        P* source_buckets = buckets;
        buckets = nullptr;
        P* target_buckets;
        P* temp_buckets1;
        P* temp_buckets2;
        for (unsigned i = 0;; i++) {
          const unsigned target_bits_count = (source_bits_count + 1) >> 1;                 // half the bits rounded up
          target_windows_count = source_windows_count << 1;                                // twice the number of bms
          const unsigned target_buckets_count = target_windows_count << target_bits_count; // new_bms*2^new_c
          CHK_IF_RETURN(cudaMallocAsync(&target_buckets, sizeof(P) * target_buckets_count * batch_size, stream));
          CHK_IF_RETURN(cudaMallocAsync(
            &temp_buckets1, sizeof(P) * source_buckets_count / 2 * batch_size,
            stream)); // for type1 reduction (strided, bottom window - evens)
          CHK_IF_RETURN(cudaMallocAsync(
            &temp_buckets2, sizeof(P) * source_buckets_count / 2 * batch_size,
            stream)); // for type2 reduction (serial, top window - odds)
          initialize_buckets_kernel<<<(target_buckets_count * batch_size + 255) / 256, 256>>>(
            target_buckets, target_buckets_count * batch_size); // initialization is needed for the odd c case

          for (unsigned j = 0; j < target_bits_count; j++) {
            const bool is_first_iter = (j == 0);
            const bool is_second_iter = (j == 1);
            const bool is_last_iter = (j == target_bits_count - 1);
            const bool is_odd_c = source_bits_count & 1;
            unsigned nof_threads =
              (((source_windows_count << target_bits_count) - source_windows_count) << (target_bits_count - 1 - j)) *
              batch_size; // nof sections to reduce (minus the section that goes to zero buckets) shifted by nof threads
                          // per section
            NUM_THREADS = max(1, min(MAX_TH, nof_threads));
            NUM_BLOCKS = (nof_threads + NUM_THREADS - 1) / NUM_THREADS;
            if (!is_odd_c || !is_first_iter) { // skip if c is odd and it's the first iteration
              single_stage_multi_reduction_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
                is_first_iter || (is_second_iter && is_odd_c) ? source_buckets : temp_buckets1,
                is_last_iter ? target_buckets : temp_buckets1, 1 << (source_bits_count - j + (is_odd_c ? 1 : 0)),
                is_last_iter ? 1 << target_bits_count : 0, 1 << target_bits_count, 0 /*=write_phase*/,
                (1 << target_bits_count) - 1, nof_threads);
            }

            nof_threads = (((source_windows_count << (source_bits_count - target_bits_count)) - source_windows_count)
                           << (target_bits_count - 1 - j)) *
                          batch_size; // nof sections to reduce (minus the section that goes to zero buckets) shifted by
                                      // nof threads per section
            NUM_THREADS = max(1, min(MAX_TH, nof_threads));
            NUM_BLOCKS = (nof_threads + NUM_THREADS - 1) / NUM_THREADS;
            single_stage_multi_reduction_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream_reduction>>>(
              is_first_iter ? source_buckets : temp_buckets2, is_last_iter ? target_buckets : temp_buckets2,
              1 << (target_bits_count - j), is_last_iter ? 1 << target_bits_count : 0,
              1 << (target_bits_count - (is_odd_c ? 1 : 0)), 1 /*=write_phase*/,
              (1 << (target_bits_count - (is_odd_c ? 1 : 0))) - 1, nof_threads);
          }
          CHK_IF_RETURN(cudaEventRecord(event_finished_reduction, stream_reduction));
          CHK_IF_RETURN(
            cudaStreamWaitEvent(stream, event_finished_reduction)); // sync streams after every write to target_buckets
          if (target_bits_count == 1) {
            // Note: the reduction ends up with 'target_windows_count' windows per batch element. Some are guaranteed
            // to be empty when target_windows_count>bitsize. for example consider bitsize=253 and c=2. The reduction
            // ends with 254 bms but the most significant one is guaranteed to be zero since the scalars are 253b.
            // precomputation and odd c can cause additional empty windows.
            nof_final_results_per_msm = min(c * nof_bms_per_msm, bitsize);
            nof_bms_per_msm = target_windows_count;
            unsigned total_nof_final_results = nof_final_results_per_msm * batch_size;

            CHK_IF_RETURN(cudaMallocAsync(&final_results, sizeof(P) * total_nof_final_results, stream));

            NUM_THREADS = 32;
            NUM_BLOCKS = (total_nof_final_results + NUM_THREADS - 1) / NUM_THREADS;
            last_pass_kernel<<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
              target_buckets, final_results, nof_final_results_per_msm, batch_size, nof_bms_per_msm, c);
            c = 1;
            CHK_IF_RETURN(cudaFreeAsync(source_buckets, stream));
            CHK_IF_RETURN(cudaFreeAsync(target_buckets, stream));
            CHK_IF_RETURN(cudaFreeAsync(temp_buckets1, stream));
            CHK_IF_RETURN(cudaFreeAsync(temp_buckets2, stream));
            CHK_IF_RETURN(cudaStreamDestroy(stream_reduction));
            break;
          }
          CHK_IF_RETURN(cudaFreeAsync(source_buckets, stream));
          CHK_IF_RETURN(cudaFreeAsync(temp_buckets1, stream));
          CHK_IF_RETURN(cudaFreeAsync(temp_buckets2, stream));
          source_buckets = target_buckets;
          target_buckets = nullptr;
          temp_buckets1 = nullptr;
          temp_buckets2 = nullptr;
          source_bits_count = target_bits_count;
          source_windows_count = target_windows_count;
          source_buckets_count = target_buckets_count;
        }
      }

      // ------- This is the final stage where bucket modules/window sums get added up with appropriate weights
      // -------
      NUM_THREADS = 32;
      NUM_BLOCKS = (batch_size + NUM_THREADS - 1) / NUM_THREADS;
      // launch the double and add kernel, a single thread per batch element
      final_accumulation_kernel<P, S><<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
        final_results, are_results_on_device ? final_result : d_allocated_final_result, batch_size,
        nof_final_results_per_msm, c);
      CHK_IF_RETURN(cudaFreeAsync(final_results, stream));

      if (!are_results_on_device)
        CHK_IF_RETURN(cudaMemcpyAsync(
          final_result, d_allocated_final_result, sizeof(P) * batch_size, cudaMemcpyDeviceToHost, stream));

      // free memory
      if (d_allocated_scalars) CHK_IF_RETURN(cudaFreeAsync(d_allocated_scalars, stream));
      if (d_allocated_points && !return_processed_points) CHK_IF_RETURN(cudaFreeAsync(d_allocated_points, stream));
      if (d_allocated_final_result) CHK_IF_RETURN(cudaFreeAsync(d_allocated_final_result, stream));
      CHK_IF_RETURN(cudaFreeAsync(buckets, stream));

      if (!is_async) CHK_IF_RETURN(cudaStreamSynchronize(stream));

      return CHK_LAST();
    }
  } // namespace


  template <typename S, typename A, typename P>
  unsigned long estimate_msm_memory(const MSMConfig& config, int msm_size, unsigned c, unsigned bitsize, int nof_chunks){
    unsigned nof_bms = (bitsize + c - 1) / c;
    unsigned nof_bms_after_precomputation = (nof_bms + config.precompute_factor - 1) / config.precompute_factor;
    unsigned long scalars_mem = sizeof(S) * msm_size * config.batch_size;
    unsigned long indices_mem = 7 * sizeof(unsigned) * msm_size * config.batch_size * nof_bms; //factor 7 as an estimation for the sorting extra memory. can be reduced by sorting separatly or changing sort algorithm
    unsigned long points_mem = sizeof(A) * msm_size * config.precompute_factor * (config.are_points_shared_in_batch? 1 : config.batch_size);
    unsigned long buckets_mem = 3 * sizeof(P) * (1<<c) * config.batch_size * nof_bms_after_precomputation; //factor 3 for the extra memory in the iterative reduction algorithm. can be reduced with some optimizations.
    if (nof_chunks > 1){
      scalars_mem = scalars_mem * 2 / nof_chunks;
      indices_mem = indices_mem * 2 / nof_chunks;
      points_mem = config.batch_size > 1 && config.are_points_shared_in_batch? points_mem * 2 : points_mem * 2 / nof_chunks;
      buckets_mem = config.batch_size > 1 ? buckets_mem / nof_chunks : buckets_mem;
    } //FIXME: fix divisions
    return scalars_mem + indices_mem + points_mem + buckets_mem;
  }


  unsigned long get_device_global_memory(int device) {
    cudaDeviceProp deviceProp;
    CHK_IF_RETURN(cudaGetDeviceProperties(&deviceProp, device));
    return deviceProp.totalGlobalMem;
  }

  template <typename S, typename A, typename P>
  int get_min_nof_chunks(const MSMConfig& config, int msm_size, unsigned c, unsigned bitsize){
    printf("get min\n");
    unsigned nof_bms = (bitsize + c - 1) / c;
    unsigned nof_bms_after_precomputation = (nof_bms + config.precompute_factor - 1) / config.precompute_factor;
    unsigned long scalars_mem = sizeof(S) * msm_size * config.batch_size;
    unsigned long indices_mem = 7 * sizeof(unsigned) * msm_size * config.batch_size * nof_bms; //factor 7 as an estimation for the sorting extra memory. can be reduced by sorting separatly or changing sort algorithm
    unsigned long points_mem = sizeof(A) * msm_size * config.precompute_factor * (config.are_points_shared_in_batch? 1 : config.batch_size);
    unsigned long buckets_mem = 3 * sizeof(P) * (1<<c) * config.batch_size * nof_bms_after_precomputation; //factor 3 for the extra memory in the iterative reduction algorithm. can be reduced with some optimizations.
    unsigned long gpu_memory = get_device_global_memory(config.ctx.device_id);
    double reduced_gpu_memory = 0.7*static_cast<double>(gpu_memory);
    double lower_bound;
    unsigned min_nof_chunks;
    // printf("pre cond\n");
    if (config.batch_size < 2){ //single msm
      if (buckets_mem > reduced_gpu_memory){
        THROW_ICICLE_ERR(IcicleError_t::InvalidArgument, "msm: c is too large");
      }
      lower_bound = static_cast<double>(2*(scalars_mem+points_mem+indices_mem)) / static_cast<double>(reduced_gpu_memory - static_cast<double>(buckets_mem));
      min_nof_chunks = static_cast<int>(lower_bound) + 1;
    }
    else{
      if (config.are_points_shared_in_batch){ //shared points batch
        if (2*points_mem > reduced_gpu_memory){
          THROW_ICICLE_ERR(IcicleError_t::InvalidArgument, "msm: msm size (including precomputation) is too large for batching");
        }
        lower_bound = static_cast<double>(2*(scalars_mem+indices_mem)+buckets_mem) / static_cast<double>(reduced_gpu_memory - static_cast<double>(2*points_mem));
        min_nof_chunks = static_cast<int>(lower_bound) + 1;
      }
      else{ //different points batch
        lower_bound = static_cast<double>(2*(scalars_mem+points_mem+indices_mem)+buckets_mem) / reduced_gpu_memory;
        min_nof_chunks = static_cast<int>(lower_bound) + 1;
      }
      if (min_nof_chunks > config.batch_size){
        THROW_ICICLE_ERR(IcicleError_t::InvalidArgument, "msm: either msm size is too large for batching or c is too large");
      }
    }
    return min_nof_chunks;
  }

  template <typename S, typename A, typename P>
  int get_optimal_nof_chunks(const MSMConfig& config, int msm_size, unsigned c, unsigned bitsize){
    // printf("get opt\n");
    /*if doesnt fit in memory:
        nof = shuch that fits
      else:
      if points/scalars on host
      nof = size dependant
      else:
      nof = 1
    */
    int min_nof_chunks = get_min_nof_chunks<S,A,P>(config, msm_size, c, bitsize);
    if (min_nof_chunks > 1) return min_nof_chunks;
    if (!config.are_points_on_device || !config.are_scalars_on_device) return 4;
    return 1;
  }


  template <typename S, typename A, typename P>
  cudaError_t msm(const S* scalars, const A* points, int msm_size, const MSMConfig& config, P* results)
  {
    const int bitsize = (config.bitsize == 0) ? S::NBITS : config.bitsize;
    cudaStream_t& stream = config.ctx.stream;

    unsigned c = (config.c == 0) ? get_optimal_c(msm_size) : config.c;
    int nof_chunks, min_nof_chunks;
    // printf("msm\n");
    if (config.nof_chunks){
      nof_chunks = config.nof_chunks;
      // unsigned long memory_estimation = estimate_msm_memory<S,A,P>(config, msm_size, c, bitsize, nof_chunks);
      // unsigned long gpu_memory = get_device_global_memory(config.ctx.device_id);
      // if (memory_estimation > static_cast<double>(gpu_memory)*0.7) {
      min_nof_chunks = get_min_nof_chunks<S,A,P>(config, msm_size, c, bitsize);
      if (min_nof_chunks>nof_chunks){
        // printf("msm memory estimation: %lu, device global memory: %lu\n",memory_estimation, gpu_memory);
        THROW_ICICLE_ERR(
          IcicleError_t::InvalidArgument, "msm: using given parameters msm wil require too much memory, try using default nof chunks");
      }
    }
    else{
      nof_chunks = get_optimal_nof_chunks<S,A,P>(config, msm_size, c, bitsize);
    }
    printf("nof chunks %d\n", nof_chunks);
    // int nof_chunks = config.nof_chunks == 0 ? get_optimal_nof_chunks() : config.nof_chunks;

    return CHK_STICKY(multi_chunked_msm(scalars, points, msm_size, nof_chunks, config, results, bitsize, c, stream));
  }

  template <typename S, typename A, typename P>
  cudaError_t multi_chunked_msm(const S* scalars, const A* points, int msm_size, int nof_chunks, const MSMConfig& config, P* results, unsigned bitsize, unsigned c, cudaStream_t stream){
    // printf("multi chunked\n");
    bool internal_are_scalars_on_device = config.are_scalars_on_device;
    bool internal_are_points_on_device = config.are_points_on_device;
    cudaStream_t transfer_stream;
    CHK_IF_RETURN(cudaStreamCreate(&transfer_stream));
    int total_size = config.batch_size * msm_size;
    bool multi_batch_mode = config.batch_size > 1;
    bool multi_points = !config.are_points_shared_in_batch;
    bool batch_same_points = multi_batch_mode && !multi_points;
    bool process_batch_same_points = batch_same_points && config.are_points_montgomery_form;
    int scalars_chunk_size = (total_size + nof_chunks - 1) / nof_chunks;
    if (multi_batch_mode) scalars_chunk_size = ((config.batch_size + nof_chunks - 1) / nof_chunks) * msm_size;
    int points_chunk_size = scalars_chunk_size * config.precompute_factor;
    int batch_chunk_size = max(1, scalars_chunk_size / msm_size);

    A* points_d;
    S* scalars_d;
    P* buckets_d;
    if ((!config.are_scalars_on_device) && nof_chunks > 1){
      CHK_IF_RETURN(cudaMallocAsync(&scalars_d, sizeof(S) * scalars_chunk_size*2, stream));
    }
    if (((!config.are_points_on_device) || process_batch_same_points) && nof_chunks > 1){
      CHK_IF_RETURN(cudaMallocAsync(&points_d, sizeof(A) * points_chunk_size*2, stream));
    }
    int sub_scalars_size = scalars_chunk_size;
    int sub_points_size = sub_scalars_size * config.precompute_factor;
    for (int i = 0; i < nof_chunks; i++)
    {
      bool is_last_iter = i == nof_chunks - 1; 
      int sub_batch_size = multi_batch_mode? sub_scalars_size / msm_size : config.batch_size;
      int sub_msm_size = multi_batch_mode? msm_size : sub_scalars_size;
      bool init_buckets = (i == 0) || multi_batch_mode;
      bool return_buckets = (!is_last_iter) && (!multi_batch_mode);
      if (i){
        internal_are_scalars_on_device = true;
        internal_are_points_on_device = true;
      }
      // printf("sub_batch_size %d sub_scalars_size %d\n", sub_batch_size, sub_scalars_size);
      bool internal_are_points_montgomery_form = (batch_same_points && i)? false : config.are_points_montgomery_form;
      bool return_points_poiter = (i == 0) && batch_same_points && (config.are_points_montgomery_form || !config.are_points_on_device);
      bool init_points = (i == 0) || !process_batch_same_points;
      CHK_IF_RETURN(bucket_method_msm(
      bitsize, c, (internal_are_scalars_on_device && !config.are_scalars_on_device? scalars_d : scalars) + (config.are_scalars_on_device? i : i%2)*scalars_chunk_size, //use scalars_d from second round if scalars are on host, o.w. use scalars, which are on device
      (internal_are_points_on_device && ((!config.are_points_on_device) || process_batch_same_points)? points_d : points) + (batch_same_points? 0 : (config.are_points_on_device? i : i%2)*points_chunk_size), //use points_d from second round if points are on host or in same points if the points were processed, o.w. use points, which are on device
      &points_d, return_points_poiter, init_points, sub_batch_size, sub_msm_size,
      config.are_points_shared_in_batch, &buckets_d, init_buckets, return_buckets ,results + (multi_batch_mode? i * batch_chunk_size : 0), internal_are_scalars_on_device,
      config.are_scalars_montgomery_form, internal_are_points_on_device, internal_are_points_montgomery_form,
      config.are_results_on_device, config.is_big_triangle, config.large_bucket_factor, config.precompute_factor,
      config.is_async, stream));
      if (is_last_iter) break;
      // copy for next iteration
      sub_scalars_size = min(total_size - scalars_chunk_size * (i + 1), scalars_chunk_size);
      if (sub_scalars_size <= 0) break; //if last chunk size is 0 - break;
      sub_points_size = sub_scalars_size * config.precompute_factor;
      if (!config.are_scalars_on_device) CHK_IF_RETURN(cudaMemcpyAsync(scalars_d + ((i+1)%2)*scalars_chunk_size, scalars + (i+1)*scalars_chunk_size, sizeof(S) * sub_scalars_size, cudaMemcpyHostToDevice, transfer_stream)); //scalars on host
      if (!config.are_points_on_device && !batch_same_points) CHK_IF_RETURN(cudaMemcpyAsync(points_d + ((i+1)%2)*points_chunk_size, points + (i+1)*points_chunk_size, sizeof(A) * sub_points_size, cudaMemcpyHostToDevice, transfer_stream)); //points on host
      cudaEvent_t finish_transfer;
      CHK_IF_RETURN(cudaEventCreateWithFlags(&finish_transfer, cudaEventDisableTiming));
      CHK_IF_RETURN(cudaEventRecord(finish_transfer, transfer_stream));
      CHK_IF_RETURN(cudaStreamWaitEvent(config.ctx.stream, finish_transfer));
      CHK_IF_RETURN(cudaEventDestroy(finish_transfer));
    }
    CHK_IF_RETURN(cudaStreamDestroy(transfer_stream));
    if ((!config.are_scalars_on_device) && nof_chunks > 1) CHK_IF_RETURN(cudaFreeAsync(scalars_d, stream));
    if (((!config.are_points_on_device) || process_batch_same_points) && nof_chunks > 1) CHK_IF_RETURN(cudaFreeAsync(points_d, stream));
    return CHK_LAST();
  }

  template <typename A, typename P>
  cudaError_t precompute_msm_points_chunk(
    const A* points,
    int points_size,
    int precompute_factor,
    int c,
    bool are_points_on_device,
    cudaStream_t stream,
    A* output_points)
  {
    CHK_INIT_IF_RETURN();

    CHK_IF_RETURN(cudaMemcpyAsync(
      output_points, points, sizeof(A) * points_size,
      are_points_on_device ? cudaMemcpyDeviceToDevice : cudaMemcpyHostToDevice, stream));

    unsigned total_nof_bms = (P::SCALAR_FF_NBITS - 1) / c + 1;
    unsigned shift = c * ((total_nof_bms - 1) / precompute_factor + 1);

    unsigned NUM_THREADS = 1 << 8;
    unsigned NUM_BLOCKS = (points_size + NUM_THREADS - 1) / NUM_THREADS;
    for (int i = 1; i < precompute_factor; i++) {
      left_shift_kernel<A, P><<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
        &output_points[(i - 1) * points_size], shift, points_size, &output_points[i * points_size]);
    }

    return CHK_LAST();
  }

  template <typename A, typename P>
  [[deprecated("Use precompute_msm_points instead.")]] cudaError_t precompute_msm_bases(
    A* bases,
    int bases_size,
    int precompute_factor,
    int _c,
    bool are_bases_on_device,
    device_context::DeviceContext& ctx,
    A* output_bases)
  {
    CHK_INIT_IF_RETURN();

    cudaStream_t& stream = ctx.stream;

    CHK_IF_RETURN(cudaMemcpyAsync(
      output_bases, bases, sizeof(A) * bases_size,
      are_bases_on_device ? cudaMemcpyDeviceToDevice : cudaMemcpyHostToDevice, stream));

    unsigned c = 16;
    unsigned total_nof_bms = (P::SCALAR_FF_NBITS - 1) / c + 1;
    unsigned shift = c * ((total_nof_bms - 1) / precompute_factor + 1);

    unsigned NUM_THREADS = 1 << 8;
    unsigned NUM_BLOCKS = (bases_size + NUM_THREADS - 1) / NUM_THREADS;
    for (int i = 1; i < precompute_factor; i++) {
      left_shift_kernel<A, P><<<NUM_BLOCKS, NUM_THREADS, 0, stream>>>(
        &output_bases[(i - 1) * bases_size], shift, bases_size, &output_bases[i * bases_size]);
    }

    return CHK_LAST();
  }

  template <typename A, typename P>
  cudaError_t chunked_precompute(const A* points, int msm_size, unsigned c, const MSMConfig& config, A* points_precomputed, int nof_chunks){
    cudaStream_t stream = config.ctx.stream;
    A *points_d;
    A *points_precomputed_d, *points_precomputed_h;
    int points_size = config.are_points_shared_in_batch? msm_size : config.batch_size * msm_size;
    bool multi_batch_mode = config.batch_size > 1;
    bool multi_points = !config.are_points_shared_in_batch;
    int chunk_size = (points_size + nof_chunks - 1) / nof_chunks;
    if (multi_batch_mode) chunk_size = ((config.batch_size + nof_chunks - 1) / nof_chunks) * msm_size;
    if (multi_batch_mode && !multi_points) nof_chunks = 1;
    if (config.are_points_on_device){
      points_precomputed_d = points_precomputed;
    }
    else{
      CHK_IF_RETURN(cudaMallocAsync(&points_d, sizeof(A) * chunk_size*2, stream));
      CHK_IF_RETURN(cudaMallocAsync(&points_precomputed_d, sizeof(A) * chunk_size*2*config.precompute_factor, stream));
      points_precomputed_h = points_precomputed;
    }
    for (int i = 0; i < nof_chunks; i++){
      int sub_msm_size = min(points_size - chunk_size * i, chunk_size);
      if (sub_msm_size <= 0) break;
      // printf("prec sub_msm_size %d\n", sub_msm_size);
      if (!config.are_points_on_device) {
        CHK_IF_RETURN(cudaMemcpyAsync(points_d + (i%2)*chunk_size, points + i*chunk_size, sizeof(A) * sub_msm_size, cudaMemcpyHostToDevice, stream)); //points are on host
        CHK_IF_RETURN((precompute_msm_points_chunk<A, P>(points_d + (i%2)*chunk_size, sub_msm_size, config.precompute_factor, c, true, stream, points_precomputed_d + (i%2)*chunk_size*config.precompute_factor)));
        CHK_IF_RETURN(cudaMemcpyAsync(points_precomputed_h + i*chunk_size*config.precompute_factor, points_precomputed_d + (i%2)*chunk_size*config.precompute_factor, sizeof(A) * sub_msm_size*config.precompute_factor, cudaMemcpyDeviceToHost, stream));
      }
      else{
        CHK_IF_RETURN((precompute_msm_points_chunk<A, P>(points + i*chunk_size, sub_msm_size, config.precompute_factor, c, true, stream, points_precomputed_d + i*chunk_size*config.precompute_factor))); //poinst are on device
      }
    }
    if (!config.are_points_on_device){
      CHK_IF_RETURN(cudaFreeAsync(points_d, stream));
      CHK_IF_RETURN(cudaFreeAsync(points_precomputed_d, stream));
    }
    return CHK_LAST();
  }

  template <typename S, typename A, typename P>
  cudaError_t precompute_msm_points(const A* points, int msm_size, const MSMConfig& config, A* output_points)
  {
    unsigned c = (config.c == 0) ? get_optimal_c(msm_size) : config.c;
    const int bitsize = (config.bitsize == 0) ? S::NBITS : config.bitsize;
    int nof_chunks = config.nof_chunks == 0 ? get_optimal_nof_chunks<S,A,P>(config, msm_size, c, bitsize) : config.nof_chunks;
    return CHK_STICKY((chunked_precompute<A, P>(points, msm_size, c, config, output_points, nof_chunks)));
  }



} // namespace msm