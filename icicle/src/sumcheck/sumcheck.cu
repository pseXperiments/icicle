

#define SHMEM_SIZE 64
#define MAX_SHMEM_LOG_SIZE 6
#define FIELD_ID BN254
#define CURVE_ID BN254

#include "../ntt/kernel_ntt.cu"
// static inline __device__ uint32_t bit_rev(uint32_t num, uint32_t log_size) { return __brev(num) >> (32 - log_size); }

// template <typename S>
// __global__ void inplace_rbo(S* arr, int size){
// 	int tid = blockIdx.x * blockDim.x + threadIdx.x;
// 	S temp = arr[tid];
// 	arr[tid] = arr[bit_rev(tid)];
// 	arr[bit_rev(tid)] = temp;
// }

template <typename S>
__global__ void mult_and_reduce_double(S *v, S *v_r, S alpha1, S alpha2, int stride, int jump_size) {
	// Allocate shared memory
	__shared__ S partial_sum[SHMEM_SIZE];

	// Calculate thread ID
	int tid = blockIdx.x * blockDim.x + threadIdx.x;

	// Load elements AND do first add of reduction
	// Vector now 2x as long as number of threads, so scale i
	int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;

	// Store first partial result instead of just the elements
	// partial_sum[threadIdx.x] = v[i] + v[i + blockDim.x];
	// partial_sum[threadIdx.x] = (S::one() - alpha) * v[2*i] + alpha * v[2*i+1] + (S::one() - alpha) * v[2*(i + blockDim.x)] + alpha * v[2*(i + blockDim.x)+1];
	S e1 = v[i*stride];
	S e2 = v[(i+2*jump_size)*stride];
	S e3 = v[(i+jump_size)*stride];
	S e4 = v[(i+3*jump_size)*stride];
	S f1 = e1 + alpha1 * (e3 - e1) + alpha2 * (e2 - e1) + alpha1 * alpha2 * (e1 + e4 - e2 - e3);

	e1 = v[(i+blockDim.x)*stride];
	e2 = v[(i+blockDim.x+2*jump_size)*stride];
	e3 = v[(i+blockDim.x+jump_size)*stride];
	e4 = v[(i+blockDim.x+3*jump_size)*stride];
	S f2 = e1 + alpha1 * (e3 - e1) + alpha2 * (e2 - e1) + alpha1 * alpha2 * (e1 + e4 - e2 - e3);
	// S e1 = v[2*i] + (v[2*i+1] - v[2*i]);
	// S e2 = v[2*(i + blockDim.x)] + (v[2*(i + blockDim.x)+1] - v[2*(i + blockDim.x)]);
	// partial_sum[threadIdx.x] = v[2*i] + v[2*(i + blockDim.x)] + alpha * (v[2*i+1] - v[2*i] + v[2*(i + blockDim.x)+1] - v[2*(i + blockDim.x)]);
	partial_sum[threadIdx.x] = f1 + f2;
	// __syncthreads();
	v[i*stride] = f1;
	v[(i + blockDim.x)*stride] = f2;
	// for (int j = 0; j < 2; j++)
	// {
	// 	partial_sum[threadIdx.x] = partial_sum[threadIdx.x] * partial_sum[threadIdx.x];
	// }
	
	__syncthreads();

	// Start at 1/2 block stride and divide by two each iteration
	for (int s = blockDim.x / 2; s > 0; s >>= 1) {
	// for (int s = blockDim.x / 2; s > 1; s >>= 1) {
		// Each thread does work unless it is further than the stride
		if (threadIdx.x < s) {
			partial_sum[threadIdx.x] = partial_sum[threadIdx.x] + partial_sum[threadIdx.x + s];
		}
		__syncthreads();
	}

	// Let the thread 0 for this block write it's result to main memory
	// Result is inexed by this block
	// if (threadIdx.x < nof_results) {
	if (threadIdx.x == 0) {
		// printf("debug tid %d, val %d\n", threadIdx.x, partial_sum[threadIdx.x]);
		// v_r[nof_results*blockIdx.x + threadIdx.x] = partial_sum[threadIdx.x];
		v_r[i*stride] = partial_sum[0];
	}
}

template <typename S>
__global__ void mult_and_reduce(S *v, S *v_r, S alpha, int stride, int jump_size) {
	// Allocate shared memory
	__shared__ S partial_sum[SHMEM_SIZE];

	// Calculate thread ID
	int tid = blockIdx.x * blockDim.x + threadIdx.x;

	// Load elements AND do first add of reduction
	// Vector now 2x as long as number of threads, so scale i
	int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;

	// Store first partial result instead of just the elements
	// partial_sum[threadIdx.x] = v[i] + v[i + blockDim.x];
	// partial_sum[threadIdx.x] = (S::one() - alpha) * v[2*i] + alpha * v[2*i+1] + (S::one() - alpha) * v[2*(i + blockDim.x)] + alpha * v[2*(i + blockDim.x)+1];
	S e1 = v[i*stride] + alpha * (v[(i+jump_size)*stride] - v[i*stride]);
	S e2 = v[(i + blockDim.x)*stride] + alpha * (v[(i + blockDim.x+jump_size)*stride] - v[(i + blockDim.x)*stride]);
	// S e1 = v[2*i] + (v[2*i+1] - v[2*i]);
	// S e2 = v[2*(i + blockDim.x)] + (v[2*(i + blockDim.x)+1] - v[2*(i + blockDim.x)]);
	// partial_sum[threadIdx.x] = v[2*i] + v[2*(i + blockDim.x)] + alpha * (v[2*i+1] - v[2*i] + v[2*(i + blockDim.x)+1] - v[2*(i + blockDim.x)]);
	partial_sum[threadIdx.x] = e1 + e2;
	// __syncthreads();
	v[i*stride] = e1;
	v[(i + blockDim.x)*stride] = e2;
	// for (int j = 0; j < 2; j++)
	// {
	// 	partial_sum[threadIdx.x] = partial_sum[threadIdx.x] * partial_sum[threadIdx.x];
	// }
	
	__syncthreads();

	// Start at 1/2 block stride and divide by two each iteration
	for (int s = blockDim.x / 2; s > 0; s >>= 1) {
	// for (int s = blockDim.x / 2; s > 1; s >>= 1) {
		// Each thread does work unless it is further than the stride
		if (threadIdx.x < s) {
			partial_sum[threadIdx.x] = partial_sum[threadIdx.x] + partial_sum[threadIdx.x + s];
		}
		__syncthreads();
	}

	// Let the thread 0 for this block write it's result to main memory
	// Result is inexed by this block
	// if (threadIdx.x < nof_results) {
	if (threadIdx.x == 0) {
		// printf("debug tid %d, val %d\n", threadIdx.x, partial_sum[threadIdx.x]);
		// v_r[nof_results*blockIdx.x + threadIdx.x] = partial_sum[threadIdx.x];
		v_r[i*stride] = partial_sum[0];
	}
}


template <typename S>
__global__ void sum_reduction(S *v, S *v_r, int stride) {
	// Allocate shared memory
	__shared__ S partial_sum[SHMEM_SIZE];

	// Calculate thread ID
	int tid = blockIdx.x * blockDim.x + threadIdx.x;

	// Load elements AND do first add of reduction
	// Vector now 2x as long as number of threads, so scale i
	int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;

	// Store first partial result instead of just the elements
	partial_sum[threadIdx.x] = v[i*stride] + v[(i + blockDim.x)*stride];
	__syncthreads();

	// Start at 1/2 block stride and divide by two each iteration
	for (int s = blockDim.x / 2; s > 0; s >>= 1) {
	// for (int s = blockDim.x / 2; s > 1; s >>= 1) {
		// Each thread does work unless it is further than the stride
		if (threadIdx.x < s) {
			partial_sum[threadIdx.x] = partial_sum[threadIdx.x] + partial_sum[threadIdx.x + s];
		}
		__syncthreads();
	}

	// Let the thread 0 for this block write it's result to main memory
	// Result is inexed by this block
	// if (threadIdx.x < nof_results) {
	if (threadIdx.x == 0) {
		// printf("debug tid %d, val %d\n", threadIdx.x, partial_sum[threadIdx.x]);
		// v_r[blockIdx.x] = partial_sum[0];
		v_r[i*stride] = partial_sum[0];
		// v_r[nof_results*blockIdx.x + threadIdx.x] = partial_sum[threadIdx.x];
	}
}

template <typename S>
__global__ void update_evals_kernel(S* evals, S alpha, int poly_size, int poly_shift, int nof_ploys){
  int threads_per_poly = poly_size/2;
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= threads_per_poly*nof_ploys) return;
	int poly_id = tid / threads_per_poly;
	int eval_id = tid % threads_per_poly;
  // evals[tid] = (S::one() - alpha) * evals[2*tid] + alpha * evals[2*tid+1];
  // evals[tid] =  evals[2*tid] + (evals[2*tid+1] - evals[2*tid]);
	// if (tid==0) printf("%d, %d, %d, %d, %d\n", poly_size, poly_id, eval_id, poly_id*poly_size*2+eval_id, poly_id*poly_size*2+eval_id+poly_size);
	// if (tid==0) printf("what12 %d %d\n",evals[poly_id*poly_size*2 + eval_id], evals[poly_id*poly_size*2 + eval_id+poly_size]);
  evals[poly_id*poly_shift + eval_id] =  evals[poly_id*poly_shift+eval_id] + alpha * (evals[poly_id*poly_shift+eval_id+threads_per_poly] - evals[poly_id*poly_shift+eval_id]);
	// if (tid==0) printf("what %d\n",evals[poly_id*poly_size*2 + eval_id]);
  // evals[tid] = (1 - alpha) * evals[2*tid] + alpha * evals[2*tid+1];
}

template <typename S>
__global__ void update_evals_double_kernel(S* evals, S alpha1, S alpha2, int poly_size, int poly_shift, int nof_ploys){
  int threads_per_poly = poly_size/4;
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= threads_per_poly*nof_ploys) return;
	int poly_id = tid / threads_per_poly;
	int eval_id = tid % threads_per_poly;
	S e1 = evals[poly_id*poly_shift+eval_id];
	S e2 = evals[poly_id*poly_shift+eval_id+2*threads_per_poly];
	S e3 = evals[poly_id*poly_shift+eval_id+threads_per_poly];
	S e4 = evals[poly_id*poly_shift+eval_id+3*threads_per_poly];
  evals[poly_id*poly_shift + eval_id] =  e1 + alpha1 * (e3 - e1) + alpha2 * (e2 - e1) + alpha1 * alpha2 * (e1 + e4 - e2 - e3);
}

template <typename S>
void accumulate(S* in, S* out, int log_size, int nof_results, int nof_rounds, cudaStream_t stream){
  int nof_steps = (log_size - nof_rounds) / MAX_SHMEM_LOG_SIZE;
  int last_step_size = (log_size - nof_rounds) % MAX_SHMEM_LOG_SIZE;
	// printf("a nof steps %d last size %d\n", nof_steps, last_step_size);
  for (int i = 0; i < nof_steps; i++)
  {
    sum_reduction<<<(1<<(log_size - nof_rounds - (MAX_SHMEM_LOG_SIZE)*(i+1))) * nof_results * nof_rounds, SHMEM_SIZE/2,0,stream>>>(i? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*i));
		// printf("a nof blocks %d\n", 1<<(log_size -(MAX_SHMEM_LOG_SIZE)*(i+1)));
		// cudaDeviceSynchronize();
  	// printf("cuda err %d\n", cudaGetLastError());
  }
  if (last_step_size) sum_reduction<<<nof_results * nof_rounds, 1<<(last_step_size-1), 0,stream>>>(nof_steps? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*nof_steps));
	// cudaDeviceSynchronize();
  // printf("cuda err last %d\n", cudaGetLastError());
}

template <typename S>
void mult_and_accumulate_double(S* in, S* out, int log_size, S alpha1, S alpha2, int nof_results, cudaStream_t stream){
  int nof_steps = (log_size - 2) / MAX_SHMEM_LOG_SIZE;
  int last_step_size = (log_size - 2) % MAX_SHMEM_LOG_SIZE;
	// printf("m nof steps %d last size %d\n", nof_steps, last_step_size);
  for (int i = 0; i < nof_steps; i++)
  {
		if (i) sum_reduction<<<(1<<(log_size - 2 - (MAX_SHMEM_LOG_SIZE)*(i+1))) * nof_results * 2, SHMEM_SIZE/2,0,stream>>>(i? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*i));
    else mult_and_reduce_double<<<(1<<(log_size - 2 - (MAX_SHMEM_LOG_SIZE)*(i+1))) * nof_results * 2, SHMEM_SIZE/2,0,stream>>>(i? out : in, out, alpha1, alpha2, 1<<(MAX_SHMEM_LOG_SIZE*i), 1<<log_size);
		// if (i) printf("r nof blocks %d\n", 1<<(log_size-(MAX_SHMEM_LOG_SIZE)*(i+1)));
		// else printf("m nof blocks %d\n", 1<<(log_size-(MAX_SHMEM_LOG_SIZE)*(i+1)));
		// cudaDeviceSynchronize();
  	// printf("cuda err %d\n", cudaGetLastError());
  }
  if (last_step_size) {
		if (nof_steps) sum_reduction<<<nof_results * 2, 1<<(last_step_size-1), 0,stream>>>(nof_steps? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*nof_steps));
		else mult_and_reduce_double<<<nof_results * 2, 1<<(last_step_size-1), 0,stream>>>(nof_steps? out : in, out, alpha1, alpha2, 1<<(MAX_SHMEM_LOG_SIZE*nof_steps), 1<<(last_step_size+2));
		// if (nof_steps) printf("r last");
		// else printf("m last");
	} 
	cudaDeviceSynchronize();
	// printf("nof res %d last_step_size %d\n", nof_results, last_step_size);
  // printf("cuda err last %d\n", cudaGetLastError());
}

template <typename S>
void mult_and_accumulate(S* in, S* out, int log_size, S alpha, int nof_results, cudaStream_t stream){
  int nof_steps = (log_size - 1) / MAX_SHMEM_LOG_SIZE;
  int last_step_size = (log_size - 1) % MAX_SHMEM_LOG_SIZE;
	// printf("m nof steps %d last size %d\n", nof_steps, last_step_size);
  for (int i = 0; i < nof_steps; i++)
  {
		if (i) sum_reduction<<<(1<<(log_size - 1 - (MAX_SHMEM_LOG_SIZE)*(i+1))) * nof_results, SHMEM_SIZE/2,0,stream>>>(i? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*i));
    else mult_and_reduce<<<(1<<(log_size - 1 - (MAX_SHMEM_LOG_SIZE)*(i+1))) * nof_results, SHMEM_SIZE/2,0,stream>>>(i? out : in, out, alpha, 1<<(MAX_SHMEM_LOG_SIZE*i), 1<<log_size);
		// if (i) printf("r nof blocks %d\n", 1<<(log_size-(MAX_SHMEM_LOG_SIZE)*(i+1)));
		// else printf("m nof blocks %d\n", 1<<(log_size-(MAX_SHMEM_LOG_SIZE)*(i+1)));
		// cudaDeviceSynchronize();
  	// printf("cuda err %d\n", cudaGetLastError());
  }
  if (last_step_size) {
		if (nof_steps) sum_reduction<<<nof_results, 1<<(last_step_size-1), 0,stream>>>(nof_steps? out : in, out, 1<<(MAX_SHMEM_LOG_SIZE*nof_steps));
		else mult_and_reduce<<<nof_results, 1<<(last_step_size-1), 0,stream>>>(nof_steps? out : in, out, alpha, 1<<(MAX_SHMEM_LOG_SIZE*nof_steps), 1<<(last_step_size+1));
		// if (nof_steps) printf("r last");
		// else printf("m last");
	} 
	// cudaDeviceSynchronize();
	// printf("nof res %d last_step_size %d\n", nof_results, last_step_size);
  // printf("cuda err last %d\n", cudaGetLastError());
}

template <typename S>
 __launch_bounds__(1)
__global__ void add_to_trace(S* trace, S* vals, int stride, int round_num, int nof_results){
	for (int i = 0; i < nof_results; i++)
	{
		trace[nof_results*round_num+1+i] = vals[i*stride];
	}
	// for (int i = 0; i < nof_results; i++)
	// {
	// 	trace[nof_results*round_num+1+i] = vals[i];
	// }
	  // trace[2*round_num+1] = vals[0];
    // trace[2*round_num+2] = vals[1];
		// printf("%d  %d\n", vals[0], vals[1]);
}

			// T[(nof_polys+1)*(nof_polys+1)*p+1] = T[(nof_polys+1)*(nof_polys+1)*p+1] + rp[0];
			// T[(nof_polys+1)*(nof_polys+1)*p+2] = T[(nof_polys+1)*(nof_polys+1)*p+2] + rp[1];
			// T[(nof_polys+1)*(nof_polys+1)*p+3] = T[(nof_polys+1)*(nof_polys+1)*p+3] + rp[2];
			// T[(nof_polys+1)*(nof_polys+1)*p+4] = T[(nof_polys+1)*(nof_polys+1)*p+4] + rp[3];
			// if (nof_polys > 1) {
			// 	T[(nof_polys+1)*(nof_polys+1)*p+5] = T[(nof_polys+1)*(nof_polys+1)*p+5] + rp[4];
			// 	T[(nof_polys+1)*(nof_polys+1)*p+6] = T[(nof_polys+1)*(nof_polys+1)*p+6] + rp[5];
			// 	T[(nof_polys+1)*(nof_polys+1)*p+7] = T[(nof_polys+1)*(nof_polys+1)*p+7] + rp[6];
			// 	T[(nof_polys+1)*(nof_polys+1)*p+8] = T[(nof_polys+1)*(nof_polys+1)*p+8] + rp[7];
			// 	T[(nof_polys+1)*(nof_polys+1)*p+9] = T[(nof_polys+1)*(nof_polys+1)*p+9] + rp[8];
			// }

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void combinations_kernel3(S* in, S* out, int poly_size, int poly_shift){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/2) return;
	S rp[4] = {S::one(), S::one(), S::one(), S::one()};
	S e1, e2;
	#pragma unroll
	for (int l = 0; l < 3; l++)
	{
	  e1 = in[l*poly_shift + tid];
	  e2 = in[l*poly_shift + tid + poly_size/2];
		rp[0] = l? rp[0]*e1 : e1; //k=0
		rp[1] = l? rp[1]*e2 : e2; //k=1
		rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
		// rp[3] = l? rp[3]*(e1 + e1 - e2) : (e1 + e1 - e2); //k=-1
		rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/2] = rp[1];
	out[tid + 2*poly_size/2] = rp[2];
	out[tid + 3*poly_size/2] = rp[3];
}

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void combinations_kernel(S* in, S* out, int poly_size, int poly_shift, int nof_polys){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/2) return;
	S rp[5] = {S::one(), S::one(), S::one(), S::one(), S::one()}; //TODO: generalize - make template version
	S e1, e2;
	#pragma unroll
	for (int l = 0; l < nof_polys; l++)
	{
	  e1 = in[l*poly_shift + tid];
	  e2 = in[l*poly_shift + tid + poly_size/2];
		rp[0] = l? rp[0]*e1 : e1; //k=0
		rp[1] = l? rp[1]*e2 : e2; //k=1
		if (nof_polys == 1) continue;
		rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
		if (nof_polys == 2) continue;
		// rp[3] = l? rp[3]*(e1 + e1 - e2) : (e1 + e1 - e2); //k=-1
		rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
		if (nof_polys == 3) continue;
		rp[4] = l? rp[4]*(e2 + e2 + e2 + e2 - e1 - e1 - e1) : (e2 + e2 + e2 + e2 - e1 - e1 - e1); //k=4 TODO: save addition using extra reg?
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/2] = rp[1];
	if (nof_polys == 1) return;
	out[tid + 2*poly_size/2] = rp[2];
	if (nof_polys == 2) return;
	out[tid + 3*poly_size/2] = rp[3];
	if (nof_polys == 3) return;
	out[tid + 4*poly_size/2] = rp[4];
}

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void combinations_double_kernel(S* in, S* out, int poly_size, int poly_shift, int nof_polys){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/4) return;
	S rp[9] = {S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one()}; //TODO: generalize - make template version
	S e1, e2, e3, e4;
	#pragma unroll 1
	for (int l = 0; l < nof_polys; l++)
	{
	  e1 = in[l*poly_shift + tid];
	  e2 = in[l*poly_shift + tid + poly_size/2];
	  e3 = in[l*poly_shift + tid + poly_size/4];
	  e4 = in[l*poly_shift + tid + 3*poly_size/4];
		rp[0] = l? rp[0]*e1 : e1; //k=0,0
		rp[1] = l? rp[1]*e2 : e2; //k=0,1
		rp[2] = l? rp[2]*e3 : e3; //k=1,0
		rp[3] = l? rp[3]*e4 : e4; //k=1,1
		if (nof_polys == 1) continue;
		rp[4] = l? rp[4]*(e2+e2-e1) : (e2+e2-e1); //k=0,2
		rp[5] = l? rp[5]*(e3+e3-e1) : (e3+e3-e1); //k=2,0
		rp[6] = l? rp[6]*(e4+e4-e3) : (e4+e4-e3); //k=1,2
		rp[7] = l? rp[7]*(e4+e4-e2) : (e4+e4-e2); //k=2,1
		rp[8] = l? rp[8]*(e4+e4+e4+e4+e1-e2-e2-e3-e3) : (e4+e4+e4+e4+e1-e2-e2-e3-e3); //k=2,2
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/4] = rp[2];
	out[tid + 2*poly_size/4] = rp[1];
	out[tid + 3*poly_size/4] = rp[3];
	if (nof_polys == 1) return;
	out[tid + 4*poly_size/4] = rp[4];
	out[tid + 5*poly_size/4] = rp[5];
	out[tid + 6*poly_size/4] = rp[6];
	out[tid + 7*poly_size/4] = rp[7];
	out[tid + 8*poly_size/4] = rp[8];
}


template <typename S>
__global__ void combinations_double_test(S* in, S* out){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	S rp[4] = {S::one(), S::one(), S::one(), S::one()};
	rp[0] = in[tid];
	rp[1] = in[tid+1];
	rp[2] = in[tid+2];
	rp[3] = in[tid+3];
	out[tid] = rp[0] * rp[1];
	out[tid+1] = rp[2] * rp[3];
	out[tid+2] = rp[2] * rp[1];
	out[tid+3] = rp[0] * rp[3];
	out[tid+4] = rp[0] * rp[2];
	out[tid+5] = rp[0] * rp[0];
	out[tid+6] = rp[1] * rp[1];
	out[tid+7] = rp[1] * rp[3];
	out[tid+8] = rp[2] * rp[2];
}
 /*
 	S T1, T2;
	T1 = in[tid];
	T2 = in[tid+1];
	out[tid] = T1;
	out[tid+1] = T2;
	T1 = in[tid+2];
	T2 = in[tid+3];
	out[tid+2] = T1;
	out[tid+3] = T2;*/
	// if (tid >= poly_size/4) return;
	// S rp[9] = {S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one()}; //TODO: generalize - make template version
	// rp[0] = in[tid + 0];
	// rp[2] = in[tid + 2];
	// rp[1] = in[tid + 1];
	// rp[3] = in[tid + 3];
	// rp[4] = in[tid + 4];
	// rp[5] = in[tid + 5];
	// rp[6] = in[tid + 6];
	// rp[7] = in[tid + 7];
	// rp[8] = in[tid + 8];
	// rp[0] = rp[2];
	// rp[2] = rp[3];
	// rp[1] = rp[4];
	// rp[3] = rp[5];
	// rp[4] = rp[6];
	// rp[5] = rp[7];
	// rp[6] = rp[8];
	// rp[7] = rp[0];
	// rp[8] = rp[1];
	// out[tid] = rp[0];
	// out[tid + 1] = rp[2];
	// out[tid + 2] = rp[1];
	// out[tid + 3] = rp[3];
	// out[tid + 4] = rp[4];
	// out[tid + 5] = rp[5];
	// out[tid + 6] = rp[6];
	// out[tid + 7] = rp[7];
	// out[tid + 8] = rp[8];

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void mult_and_combine_double(S* in, S* out, int poly_size, int poly_shift, int nof_polys, S alpha1, S alpha2){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/4) return;
	S rp[9] = {S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one()}; //TODO: generalize - make template version
	S e1, e2, e3, e4, f1, f2, f3, f4;
	#pragma unroll 1
	for (int l = 0; l < nof_polys; l++)
	{
		f1 = in[l*poly_shift + tid];
		f2 = in[l*poly_shift + tid + 2*poly_size];
		f3 = in[l*poly_shift + tid + poly_size];
		f4 = in[l*poly_shift + tid + 3*poly_size];
		e1 = f1 + alpha1 * (f3 - f1) + alpha2 * (f2 - f1) + alpha1 * alpha2 * (f1 + f4 - f2 - f3);
		f1 = in[l*poly_shift + 2*poly_size/4 + tid];
		f2 = in[l*poly_shift + 2*poly_size/4 + tid + 2*poly_size];
		f3 = in[l*poly_shift + 2*poly_size/4 + tid + poly_size];
		f4 = in[l*poly_shift + 2*poly_size/4 + tid + 3*poly_size];
		e2 = f1 + alpha1 * (f3 - f1) + alpha2 * (f2 - f1) + alpha1 * alpha2 * (f1 + f4 - f2 - f3);
		f1 = in[l*poly_shift + poly_size/4 + tid];
		f2 = in[l*poly_shift + poly_size/4 + tid + 2*poly_size];
		f3 = in[l*poly_shift + poly_size/4 + tid + poly_size];
		f4 = in[l*poly_shift + poly_size/4 + tid + 3*poly_size];
		e3 = f1 + alpha1 * (f3 - f1) + alpha2 * (f2 - f1) + alpha1 * alpha2 * (f1 + f4 - f2 - f3);
		f1 = in[l*poly_shift + 3*poly_size/4 + tid];
		f2 = in[l*poly_shift + 3*poly_size/4 + tid + 2*poly_size];
		f3 = in[l*poly_shift + 3*poly_size/4 + tid + poly_size];
		f4 = in[l*poly_shift + 3*poly_size/4 + tid + 3*poly_size];
		e4 = f1 + alpha1 * (f3 - f1) + alpha2 * (f2 - f1) + alpha1 * alpha2 * (f1 + f4 - f2 - f3);
		in[l*poly_shift + tid] = e1;
		in[l*poly_shift + tid + poly_size/2] = e2;
		in[l*poly_shift + tid + poly_size/4] = e3;
		in[l*poly_shift + tid + 3*poly_size/4] = e4;
		rp[0] = l? rp[0]*e1 : e1; //k=0,0
		rp[1] = l? rp[1]*e2 : e2; //k=0,1
		rp[2] = l? rp[2]*e3 : e3; //k=1,0
		rp[3] = l? rp[3]*e4 : e4; //k=1,1
		if (nof_polys == 1) continue;
		rp[4] = l? rp[4]*(e2+e2-e1) : (e2+e2-e1); //k=0,2
		rp[5] = l? rp[5]*(e3+e3-e1) : (e3+e3-e1); //k=2,0
		rp[6] = l? rp[6]*(e4+e4-e3) : (e4+e4-e3); //k=1,2
		rp[7] = l? rp[7]*(e4+e4-e2) : (e4+e4-e2); //k=2,1
		rp[8] = l? rp[8]*(e4+e4+e4+e4+e1-e2-e2-e3-e3) : (e4+e4+e4+e4+e1-e2-e2-e3-e3); //k=2,2
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/4] = rp[2];
	out[tid + 2*poly_size/4] = rp[1];
	out[tid + 3*poly_size/4] = rp[3];
	if (nof_polys == 1) return;
	out[tid + 4*poly_size/4] = rp[4];
	out[tid + 5*poly_size/4] = rp[5];
	out[tid + 6*poly_size/4] = rp[6];
	out[tid + 7*poly_size/4] = rp[7];
	out[tid + 8*poly_size/4] = rp[8];
}

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void mult_and_combine3(S* in, S* out, int poly_size, int poly_shift, S alpha){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/2) return;
	S rp[4] = {S::one(), S::one(), S::one(), S::one()};
	S e1, e2;
	#pragma unroll
	for (int l = 0; l < 3; l++)
	{
		e1 = in[l*poly_shift + tid] + alpha * (in[l*poly_shift + tid + poly_size] - in[l*poly_shift + tid]);
		e2 = in[l*poly_shift + tid + poly_size/2] + alpha * (in[l*poly_shift + tid + poly_size/2 + poly_size] - in[l*poly_shift + tid + poly_size/2]);
		in[l*poly_shift + tid] = e1;
		in[l*poly_shift + tid + poly_size/2] = e2;
		rp[0] = rp[0]*e1;
		rp[1] = rp[1]*e2;
		rp[2] = rp[2]*(e2 + e2 - e1);
		rp[3] = rp[3]*(e2 + e2 + e2 - e1 - e1);
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/2] = rp[1];
	out[tid + 2*poly_size/2] = rp[2];
	out[tid + 3*poly_size/2] = rp[3];
}

template <typename S>
// __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
__global__ void mult_and_combine(S* in, S* out, int poly_size, int poly_shift, int nof_polys, S alpha){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid >= poly_size/2) return;
	S rp[5] = {S::one(), S::one(), S::one(), S::one(), S::one()}; //TODO: generalize
	S e1, e2;
	#pragma unroll
	for (int l = 0; l < nof_polys; l++)
	{
		e1 = in[l*poly_shift + tid] + alpha * (in[l*poly_shift + tid + poly_size] - in[l*poly_shift + tid]);
		e2 = in[l*poly_shift + tid + poly_size/2] + alpha * (in[l*poly_shift + tid + poly_size/2 + poly_size] - in[l*poly_shift + tid + poly_size/2]);
		in[l*poly_shift + tid] = e1;
		in[l*poly_shift + tid + poly_size/2] = e2;
		rp[0] = rp[0]*e1;
		rp[1] = rp[1]*e2;
		if (nof_polys == 1) continue;
		rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
		if (nof_polys == 2) continue;
		rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
		if (nof_polys == 3) continue;
		rp[4] = l? rp[4]*(e2 + e2 + e2 + e2 - e1 - e1 - e1) : (e2 + e2 + e2 + e2 - e1 - e1 - e1); //k=4
	}
	out[tid] = rp[0];
	out[tid + 1*poly_size/2] = rp[1];
	if (nof_polys == 1) return;
	out[tid + 2*poly_size/2] = rp[2];
	if (nof_polys == 2) return;
	out[tid + 3*poly_size/2] = rp[3];
	if (nof_polys == 3) return;
	out[tid + 4*poly_size/2] = rp[4];
}

// template <typename S, int M>
// // __global__ void combinations_kernel(S* in, S* out, S (*combine_func)()){
// __global__ void combinations_kernel(S* in, S* out){
// 	int tid = blockIdx.x * blockDim.x + threadIdx.x;
// 	S rp = s::one;
// 	#pragma unroll
// 	for (int k = 0; k < M+1; k++)
// 	{
// 		#pragma unroll
// 		for (int l = 0; l < M; i++)
// 		{
// 			rp *= in[2*tid] * (1 - k) + in[2*tid + 1] * k;
// 		}
// 	}
// }

// template <typename S>
// __device__ S simple_combine(S* f){
// 	return f[0]*f[1]*f[2]
// }

template <typename S>
S my_hash(){
	S val = S::one() + S::one();
	val = val + val;
	val = val + val; 
	return val + S::one() + S::one();
}

template <typename S>
void sumcheck_alg1(S* evals, S* t, S* T, S C, int n, bool reorder, cudaStream_t stream){
	if (reorder) reorder_digits_inplace_and_normalize_kernel<<<1<<(max(n-6,0)),64,0,stream>>>(evals, n, false, mxntt::eRevType::NaturalToRev, false, S::one());
	// S alpha = 1;
	// S alpha = S::one();
	S alpha = my_hash<S>();
	// S alpha = S::rand_host();
  // S alpha = my_hash(/*T, C*/);
  // S rp_even, rp_odd;
  for (int p = 0; p < n-1; p++)
  {
    int nof_threads = 1<<(n-1-p);
		printf("reg nof threads %d\n", nof_threads);
    // move update kernel here and unify
    // reduction_kernel<<<nof_threads>>>(evals, t, n-p); //accumulation
    accumulate(evals, t, n-p, 2, 1, stream); //accumulation
		// cudaDeviceSynchronize();
		// printf("cuda a err %d\n", cudaGetLastError());
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, 2);
		// cudaDeviceSynchronize();
		// printf("cuda t err %d\n", cudaGetLastError());
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		int NOF_THREADS = min(256,nof_threads);
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
    update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, 1<<(n-p), 0, 1); //phase 3
		// cudaDeviceSynchronize();
		// printf("cuda err u %d\n", cudaGetLastError());
		#ifdef DEBUG
		break;
		#endif
  }
	add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n-1, 2);
}

template <typename S>
void sumcheck_alg1_unified(S* evals, S* t, S* T, S C, int n, bool reorder, cudaStream_t stream){
	if (reorder) reorder_digits_inplace_and_normalize_kernel<<<1<<(max(n-6,0)),64,0,stream>>>(evals, n, false, mxntt::eRevType::NaturalToRev, false, S::one());
	// S alpha = 1;
	// S alpha = S::one() + S::one();
	S alpha = my_hash<S>();
	// S alpha = S::rand_host();
  // S alpha = my_hash(/*T, C*/);
  // S rp_even, rp_odd;
  for (int p = 0; p < n-1; p++)
  // for (int p = 0; p < 2; p++)
  {
    int nof_threads = 1<<(n-1-p);
		// printf("nof threads %d\n", nof_threads);
    // move update kernel here and unify
    // reduction_kernel<<<nof_threads>>>(evals, t, n-p); //accumulation
    if (p) mult_and_accumulate(evals, t, n-p, alpha, 2, stream); //accumulation
		else accumulate(evals, t, n-p, 2, 1, stream);
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, 2);
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		// int NOF_THREADS = 256;
		// int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha); //phase 3
		#ifdef DEBUG
		if (p) break;
		#endif
  }
	#ifndef DEBUG
	update_evals_kernel<<<1, 2,0, stream>>>(evals, alpha, 4, 0, 1);
	#endif
	add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n-1, 2);
}

template <typename S>
void sumcheck_alg3_poly3(S* evals, S* t, S* T, S C, int n, bool reorder, cudaStream_t stream){
	if (reorder) reorder_digits_inplace_and_normalize_kernel<<<1<<(max(n-6,0)),64,0,stream>>>(evals, n, false, mxntt::eRevType::NaturalToRev, false, S::one());
	// S alpha = 1;
	// S alpha = S::one();
	S alpha = my_hash<S>();
	// S alpha = S::rand_host();
  // S alpha = my_hash(/*T, C*/);
  // S rp_even, rp_odd;
  for (int p = 0; p < n; p++)
  {
    int nof_threads = 1<<(n-1-p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		// printf("nof threads %d\n", nof_threads);
    // move update kernel here and unify
    // reduction_kernel<<<nof_threads>>>(evals, t, n-p); //accumulation
		combinations_kernel3<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n);
		// cudaDeviceSynchronize();
		// printf("cuda err u %d\n", cudaGetLastError());
		if (p != n-1) accumulate(t, t, n-p, 4, 1, stream);
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, 4);
		// cudaDeviceSynchronize();
		// printf("cuda err u %d\n", cudaGetLastError());
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		nof_threads = 3<<(n-1-p);
		NOF_THREADS = 64;
		NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
    if (p != n-1) update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, 1<<(n-p), 1<<n, 3); //phase 3
		// cudaDeviceSynchronize();
		// printf("cuda err u %d\n", cudaGetLastError());
		// S h_evals_temp[64*3];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * (64*3), cudaMemcpyDeviceToHost);
		// if (p){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 64*3; i++)
		// {
		// 	if (i % 64 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
  }
	// update_evals_kernel<<<1, 2,0, stream>>>(evals, alpha);
	// add_to_trace<<<1,1,0,stream>>>(T, evals, 1<<n, n-1, 4);
}

template <typename S>
void sumcheck_alg3_poly3_unified(S* evals, S* t, S* T, S C, int n, cudaStream_t stream){
	// S alpha = 1;
	// S alpha = S::one();
	// S alpha = S::rand_host();
  S alpha = my_hash<S>();
  // S rp_even, rp_odd;
  for (int p = 0; p < n; p++)
  {
    int nof_threads = 1<<(n-1-p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		// printf("nof threads %d\n", nof_threads);
    // move update kernel here and unify
    // reduction_kernel<<<nof_threads>>>(evals, t, n-p); //accumulation
		if (p) mult_and_combine3<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n, alpha);
		else combinations_kernel3<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n);
		accumulate(t, t, n-p, 4, 1, stream);
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, 4);
		// cudaDeviceSynchronize();
		// printf("cuda err u %d\n", cudaGetLastError());
		// S h_evals_temp[8*3];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * (8*3), cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 8*3; i++)
		// {
		// 	if (i % 8 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, nof_threads); //phase 3
  }
	// update_evals_kernel<<<1, 2,0, stream>>>(evals, alpha, 2);
	// add_to_trace<<<1,1,0,stream>>>(T, evals, n-1, 4);
}


template <typename S>
void sumcheck_generic_unified(S* evals, S* t, S* T, S C, int n, int nof_polys, cudaStream_t stream){
	// S alpha = 1;
	// S alpha = S::one();
	// S alpha = S::rand_host();
  S alpha = my_hash<S>();
  // S alpha = S::zero();
  // S rp_even, rp_odd;
  for (int p = 0; p < n; p++)
  {
		// alpha = p%2? S::zero() : S::one();
    int nof_threads = 1<<(n-1-p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		if (nof_polys == 1){
		  if (p) mult_and_accumulate(evals, t, n-p, alpha, 2, stream); //accumulation
			else accumulate(evals, t, n-p, 2, 1, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err a %d\n", cudaGetLastError());
			if (p == n-1) break;
		}
		else {
			if (p) mult_and_combine<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n, nof_polys, alpha);
			else combinations_kernel<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n, nof_polys);
			// cudaDeviceSynchronize();
			// printf("cuda err b %d\n", cudaGetLastError());
			accumulate(t, t, n-p, nof_polys+1, 1, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err c %d\n", cudaGetLastError());
		}
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, nof_polys+1);
		// cudaDeviceSynchronize();
		// printf("cuda err d %d\n", cudaGetLastError());
		// S h_evals_temp[16*2];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16*2, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 16*2; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, nof_threads); //phase 3
  }
	if (nof_polys == 1){
		if (n>1) update_evals_kernel<<<1, 2,0, stream>>>(evals, alpha, 4, 0, 1);
		add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n-1, 2);
	}
}

template <typename S>
void sumcheck_double_round_unified(S* evals, S* t, S* T, S C, int n, int nof_polys, cudaStream_t stream){
	// S alpha = 1;
	// S alpha = S::one();
	// S alpha = S::rand_host();
	S alpha1 = my_hash<S>();
  S alpha2 = my_hash<S>() + my_hash<S>();
	// S alpha1 = S::zero();
	// S alpha2 = S::zero();
  // S alpha = S::zero();
  // S rp_even, rp_odd;
  for (int p = 0; p < n/2; p++)
  {
		// alpha = p%2? S::zero() : S::one();
    int nof_threads = 1<<(n-2-2*p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		if (nof_polys == 1){
		  if (p) mult_and_accumulate_double(evals, t, n-2*p, alpha1, alpha2, 2, stream); //accumulation
			else accumulate(evals, t, n-2*p, 2, 2, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err a %d\n", cudaGetLastError());
			if (p == n/2-1) break;
		}
		else {
			if (p) mult_and_combine_double<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-2*p), 1<<n, nof_polys, alpha1, alpha2);
			else combinations_double_kernel<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-2*p), 1<<n, nof_polys);
			// cudaDeviceSynchronize();
			// printf("cuda err b %d\n", cudaGetLastError());
			accumulate(t, t, n-2*p, (nof_polys+1)*(nof_polys+1), 2, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err c %d\n", cudaGetLastError());
		}
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-2-2*p), p, (nof_polys+1)*(nof_polys+1));
		// cudaDeviceSynchronize();
		// printf("cuda err d %d\n", cudaGetLastError());
		// S h_evals_temp[16*2];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16*2, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 16*2; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, nof_threads); //phase 3
  }
	if (nof_polys == 1){
		if (n>2) update_evals_double_kernel<<<1, 4,0, stream>>>(evals, alpha1, alpha2, 16, 0, 1);
		add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n/2-1, 4);
		// S h_evals_temp[16];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",n/2-1);
		// for (int i = 0; i < 16; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
	}
}

template <typename S>
void sumcheck_double_round_separate(S* evals, S* t, S* T, S C, int n, int nof_polys, cudaStream_t stream){
	// S alpha = 1;
	// S alpha = S::one();
	// S alpha = S::rand_host();
	S alpha1 = my_hash<S>();
  S alpha2 = my_hash<S>() + my_hash<S>();
	// S alpha1 = S::zero();
	// S alpha2 = S::zero();
  // S alpha = S::zero();
  // S rp_even, rp_odd;
  for (int p = 0; p < n/2; p++)
  {
		// alpha = p%2? S::zero() : S::one();
    int nof_threads = 1<<(n-2-2*p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		if (nof_polys == 1){
			accumulate(evals, t, n-2*p, 2, 2, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err a %d\n", cudaGetLastError());
			if (p == n/2-1) break;
		}
		else {
			combinations_double_kernel<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-2*p), 1<<n, nof_polys);
			// combinations_double_test<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t);
			// cudaDeviceSynchronize();
			// printf("cuda err b %d\n", cudaGetLastError());
			accumulate(t, t, n-2*p, (nof_polys+1)*(nof_polys+1), 2, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err c %d\n", cudaGetLastError());
		}
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-2-2*p), p, (nof_polys+1)*(nof_polys+1));

		nof_threads = nof_polys<<(n-2-2*p);
		NOF_THREADS = 64;
		NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
    if (p != n/2-1) update_evals_double_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha1, alpha2, 1<<(n-2*p), 1<<n, nof_polys); //phase 3
		// cudaDeviceSynchronize();
		// printf("cuda err d %d\n", cudaGetLastError());
		// S h_evals_temp[16*2];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16*2, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 16*2; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, nof_threads); //phase 3
  }
	if (nof_polys == 1){
		// update_evals_double_kernel<<<1, 4,0, stream>>>(evals, alpha1, alpha2, 16, 0, 1);
		add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n/2-1, 4);
		// S h_evals_temp[16];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",n/2-1);
		// for (int i = 0; i < 16; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
	}
}

template <typename S>
void sumcheck_generic_separate(S* evals, S* t, S* T, S C, int n, int nof_polys, cudaStream_t stream){
	// S alpha = 1;
	// S alpha = S::one();
	// S alpha = S::rand_host();
	S alpha = my_hash<S>();
	// S alpha1 = S::zero();
	// S alpha2 = S::zero();
  // S alpha = S::zero();
  // S rp_even, rp_odd;
  for (int p = 0; p < n; p++)
  {
		// alpha = p%2? S::zero() : S::one();
    int nof_threads = 1<<(n-1-p);
		int NOF_THREADS = 64;
		int NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
		if (nof_polys == 1){
			accumulate(evals, t, n-p, 2, 1, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err a %d\n", cudaGetLastError());
			if (p == n-1) break;
		}
		else {
			combinations_kernel<<<NOF_BLOCKS, NOF_THREADS,0,stream>>>(evals, t, 1<<(n-p), 1<<n, nof_polys);
			// cudaDeviceSynchronize();
			// printf("cuda err b %d\n", cudaGetLastError());
			accumulate(t, t, n-p, nof_polys+1, 1, stream);
			// cudaDeviceSynchronize();
			// printf("cuda err c %d\n", cudaGetLastError());
		}
		add_to_trace<<<1,1,0,stream>>>(T, t, 1<<(n-1-p), p, nof_polys+1);

		nof_threads = nof_polys<<(n-1-p);
		NOF_THREADS = 64;
		NOF_BLOCKS = (nof_threads + NOF_THREADS - 1) / NOF_THREADS;
    if (p != n-1) update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, 1<<(n-p), 1<<n, nof_polys); //phase 3
		// cudaDeviceSynchronize();
		// printf("cuda err d %d\n", cudaGetLastError());
		// S h_evals_temp[16*2];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16*2, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",p);
		// for (int i = 0; i < 16*2; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
    // T[2*p+1] = t[0];
    // T[2*p+2] = t[1];
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
    // update_evals_kernel<<<NOF_BLOCKS, NOF_THREADS,0, stream>>>(evals, alpha, nof_threads); //phase 3
  }
	if (nof_polys == 1){
		// update_evals_double_kernel<<<1, 4,0, stream>>>(evals, alpha1, alpha2, 16, 0, 1);
		add_to_trace<<<1,1,0,stream>>>(T, evals, 1, n-1, 2);
		// S h_evals_temp[16];
		// cudaMemcpy(h_evals_temp, evals, sizeof(S) * 16, cudaMemcpyDeviceToHost);
		// if (1){
		// printf("round %d evals:\n",n/2-1);
		// for (int i = 0; i < 16; i++)
		// {
		// 	if (i % 16 == 0) printf("\n");
		// 	std::cout << i << " " << h_evals_temp[i] << std::endl;
		// }
		// }
	}
}

template <typename S>
void sumcheck_alg1_ref(S* evals, S* t, S* T, S C, int n){
  // S alpha = my_hash(/*T, C*/);
	// S alpha = 1;
	// S alpha = S::one() + S::one();
	S alpha = my_hash<S>();
  S rp_bottom, rp_top;
  for (int p = 0; p < n; p++)
  {
		// rp_even = 0; rp_odd = 0;
		rp_bottom = S::zero(); rp_top = S::zero();
		// printf("evals\n");
		// for (int i = 0; i < 1<<(n-p); i++)
		// {
		// 	printf("%d, ",evals[i]);
		// }
		// printf("\n");
		for (int i = 0; i < 1<<(n-1-p); i++)
		{
			rp_bottom = rp_bottom + evals[i];
			rp_top = rp_top + evals[i+(1<<(n-1-p))];
		}
    T[2*p+1] = rp_bottom;
    T[2*p+2] = rp_top;
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		// alpha = 1;
		// alpha = S::one();
		for (int i = 0; i < 1<<(n-1-p); i++)
		{
			t[i] = (S::one() - alpha) * evals[i] + alpha * evals[i+(1<<(n-1-p))];
			// t[i] = (1-alpha)*evals[2*i] + alpha*evals[2*i+1];
		}
		for (int i = 0; i < 1<<(n-1-p); i++)
		{
			evals[i] = t[i];
		}
  }
}

template <typename S>
void sumcheck_alg3_ref(S* evals, S* t, S* T, S C, int n){
  // S alpha = my_hash(/*T, C*/);
	// S alpha = 1;
	// S alpha = S::one() + S::one();
	S alpha = my_hash<S>();
  
  for (int p = 0; p < n; p++)
  {

		// rp_even = 0; rp_odd = 0;
		// printf("evals\n");
		// for (int i = 0; i < 1<<(n-p); i++)
		// {
		// 	printf("%d, ",evals[i]);
		// }
		// printf("\n");
		for (int i = 0; i < 1<<(n-1-p); i++)
		{
			S rp[4] = {S::one(), S::one(), S::one(), S::one()};
			for (int l = 0; l < 3; l++)
			{
				S e1 = evals[(l<<(n-p)) + i];
				S e2 = evals[(l<<(n-p)) + i + (1<<(n-1-p))];
				rp[0] = l? rp[0]*e1 : e1; //k=0
				rp[1] = l? rp[1]*e2 : e2; //k=1
				rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
				// rp[3] = l? rp[3]*(e1 + e1 - e2) : (e1 + e1 - e2); //k=-1
				rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
			}
			T[4*p+1] = T[4*p+1] + rp[0];
			T[4*p+2] = T[4*p+2] + rp[1];
			T[4*p+3] = T[4*p+3] + rp[2];
			T[4*p+4] = T[4*p+4] + rp[3];
		}
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		// alpha = 1;
		// alpha = S::one();
		for (int l = 0; l < 3; l++)
		{
			for (int i = 0; i < 1<<(n-1-p); i++)
			{
				t[(l<<(n-1-p)) + i] = (S::one() - alpha) * evals[(l<<(n-p)) + i] + alpha * evals[(l<<(n-p)) + i + (1<<(n-1-p))];
				// t[i] = (1-alpha)*evals[2*i] + alpha*evals[2*i+1];
			}
		}
// 		if (1)
// {		printf("ref round %d evals:\n",p);
// 		for (int i = 0; i < 3<<(n-p); i++)
// 		{
// 			std::cout << i << " " << evals[i] << std::endl;
// 		}}
		for (int i = 0; i < 3<<(n-1-p); i++)
		{
			evals[i] = t[i];
		}
  }
}

template <typename S>
void sumcheck_generic_ref(S* evals, S* t, S* T, S C, int n, int nof_polys){
  // S alpha = my_hash(/*T, C*/);
	// S alpha = 1;
	// S alpha = S::one() + S::one();
	S alpha = my_hash<S>();
  
  for (int p = 0; p < n; p++)
  {

		// rp_even = 0; rp_odd = 0;
		// printf("evals\n");
		// for (int i = 0; i < 1<<(n-p); i++)
		// {
		// 	printf("%d, ",evals[i]);
		// }
		// printf("\n");
		for (int i = 0; i < 1<<(n-1-p); i++)
		{
			S rp[5] = {S::one(), S::one(), S::one(), S::one(), S::one()};
			for (int l = 0; l < nof_polys; l++)
			{
				S e1 = evals[(l<<(n-p)) + i];
				S e2 = evals[(l<<(n-p)) + i + (1<<(n-1-p))];
				rp[0] = l? rp[0]*e1 : e1; //k=0
				rp[1] = l? rp[1]*e2 : e2; //k=1
				if (nof_polys > 1) rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
				if (nof_polys > 2) rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
				if (nof_polys > 3) rp[4] = l? rp[4]*(e2 + e2 + e2 + e2 - e1 - e1 - e1) : (e2 + e2 + e2 + e2 - e1 - e1 - e1); //k=4
			}
			T[(nof_polys+1)*p+1] = T[(nof_polys+1)*p+1] + rp[0];
			T[(nof_polys+1)*p+2] = T[(nof_polys+1)*p+2] + rp[1];
			if (nof_polys > 1) T[(nof_polys+1)*p+3] = T[(nof_polys+1)*p+3] + rp[2];
			if (nof_polys > 2) T[(nof_polys+1)*p+4] = T[(nof_polys+1)*p+4] + rp[3];
			if (nof_polys > 3) T[(nof_polys+1)*p+5] = T[(nof_polys+1)*p+5] + rp[4];
		}
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		// alpha = 1;
		// alpha = S::one();
		for (int l = 0; l < nof_polys; l++)
		{
			for (int i = 0; i < 1<<(n-1-p); i++)
			{
				t[(l<<(n-1-p)) + i] = (S::one() - alpha) * evals[(l<<(n-p)) + i] + alpha * evals[(l<<(n-p)) + i + (1<<(n-1-p))];
				// t[i] = (1-alpha)*evals[2*i] + alpha*evals[2*i+1];
			}
		}
// 		if (1)
// {		printf("ref round %d evals:\n",p);
// 		for (int i = 0; i < 3<<(n-p); i++)
// 		{
// 			std::cout << i << " " << evals[i] << std::endl;
// 		}}
		for (int i = 0; i < nof_polys<<(n-1-p); i++)
		{
			evals[i] = t[i];
		}
  }
}

template <typename S>
void sumcheck_double_round_ref(S* evals, S* t, S* T, S C, int n, int nof_polys){
  // S alpha = my_hash(/*T, C*/);
	// S alpha = 1;
	// S alpha = S::one() + S::one();
	// S alpha = my_hash<S>();
	S alpha1 = my_hash<S>();
  S alpha2 = my_hash<S>() + my_hash<S>();
	// S alpha1 = S::zero();
	// S alpha2 = S::zero();
	// S alpha2 = S::zero();
  
  for (int p = 0; p < n/2; p++)
  {

		// rp_even = 0; rp_odd = 0;
		// printf("evals\n");
		// for (int i = 0; i < 1<<(n-p); i++)
		// {
		// 	printf("%d, ",evals[i]);
		// }
		// printf("\n");
		for (int i = 0; i < 1<<(n-2-2*p); i++)
		{
			S rp[9] = {S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one(), S::one()};
			for (int l = 0; l < nof_polys; l++)
			{
				S e1 = evals[(l<<(n-2*p)) + i];
				S e2 = evals[(l<<(n-2*p)) + i + (1<<(n-1-2*p))];
				S e3 = evals[(l<<(n-2*p)) + i + (1<<(n-2-2*p))];
				S e4 = evals[(l<<(n-2*p)) + i + (1<<(n-1-2*p)) + (1<<(n-2-2*p))];
				//e1 + k1 * (e3 - e1) + k2 * (e2 - e1) + k1 * k2 * (e1 + e4 - e2 - e3);
				rp[0] = l? rp[0]*e1 : e1; //k=0,0
				rp[1] = l? rp[1]*e2 : e2; //k=0,1
				rp[2] = l? rp[2]*e3 : e3; //k=1,0
				rp[3] = l? rp[3]*e4 : e4; //k=1,1
				if (nof_polys == 1) continue;
				rp[4] = l? rp[4]*(e2+e2-e1) : (e2+e2-e1); //k=0,2
				rp[5] = l? rp[5]*(e3+e3-e1) : (e3+e3-e1); //k=2,0
				rp[6] = l? rp[6]*(e4+e4-e3) : (e4+e4-e3); //k=1,2
				rp[7] = l? rp[7]*(e4+e4-e2) : (e4+e4-e2); //k=2,1
				rp[8] = l? rp[8]*(e4+e4+e4+e4+e1-e2-e2-e3-e3) : (e4+e4+e4+e4+e1-e2-e2-e3-e3); //k=2,2
				// if (nof_polys > 1) rp[2] = l? rp[2]*(e2 + e2 - e1) : (e2 + e2 - e1); //k=2
				// if (nof_polys > 2) rp[3] = l? rp[3]*(e2 + e2 + e2 - e1 - e1) : (e2 + e2 + e2 - e1 - e1); //k=3
				// if (nof_polys > 3) rp[4] = l? rp[4]*(e2 + e2 + e2 + e2 - e1 - e1 - e1) : (e2 + e2 + e2 + e2 - e1 - e1 - e1); //k=4
			}
			T[(nof_polys+1)*(nof_polys+1)*p+1] = T[(nof_polys+1)*(nof_polys+1)*p+1] + rp[0];
			T[(nof_polys+1)*(nof_polys+1)*p+2] = T[(nof_polys+1)*(nof_polys+1)*p+2] + rp[2];
			T[(nof_polys+1)*(nof_polys+1)*p+3] = T[(nof_polys+1)*(nof_polys+1)*p+3] + rp[1];
			T[(nof_polys+1)*(nof_polys+1)*p+4] = T[(nof_polys+1)*(nof_polys+1)*p+4] + rp[3];
			if (nof_polys > 1) {
				T[(nof_polys+1)*(nof_polys+1)*p+5] = T[(nof_polys+1)*(nof_polys+1)*p+5] + rp[4];
				T[(nof_polys+1)*(nof_polys+1)*p+6] = T[(nof_polys+1)*(nof_polys+1)*p+6] + rp[5];
				T[(nof_polys+1)*(nof_polys+1)*p+7] = T[(nof_polys+1)*(nof_polys+1)*p+7] + rp[6];
				T[(nof_polys+1)*(nof_polys+1)*p+8] = T[(nof_polys+1)*(nof_polys+1)*p+8] + rp[7];
				T[(nof_polys+1)*(nof_polys+1)*p+9] = T[(nof_polys+1)*(nof_polys+1)*p+9] + rp[8];
			}
			// if (nof_polys > 1) T[(nof_polys+1)*p+3] = T[(nof_polys+1)*p+3] + rp[2];
			// if (nof_polys > 2) T[(nof_polys+1)*p+4] = T[(nof_polys+1)*p+4] + rp[3];
			// if (nof_polys > 3) T[(nof_polys+1)*p+5] = T[(nof_polys+1)*p+5] + rp[4];
		}
    // alpha = my_hash(/*alpha, t[0], t[1]*/); //phase 2
		// alpha = 1;
		// alpha = S::one();
		for (int l = 0; l < nof_polys; l++)
		{
			for (int i = 0; i < 1<<(n-2-2*p); i++)
			{
				S e1 = evals[(l<<(n-2*p)) + i];
				S e2 = evals[(l<<(n-2*p)) + i + (1<<(n-1-2*p))];
				S e3 = evals[(l<<(n-2*p)) + i + (1<<(n-2-2*p))];
				S e4 = evals[(l<<(n-2*p)) + i + (1<<(n-1-2*p)) + (1<<(n-2-2*p))];
				t[(l<<(n-2-2*p)) + i] = e1 + alpha1 * (e3 - e1) + alpha2 * (e2 - e1) + alpha1 * alpha2 * (e1 + e4 - e2 - e3);
				// t[i] = (1-alpha)*evals[2*i] + alpha*evals[2*i+1];
			}
		}
// 		if (1)
// {		printf("ref round %d evals:\n",p);
// 		for (int i = 0; i < nof_polys<<(n-2*p); i++)
// 		{
// 			std::cout << i << " " << evals[i] << std::endl;
// 		}}
		for (int i = 0; i < nof_polys<<(n-2-2*p); i++)
		{
			evals[i] = t[i];
		}
  }
}