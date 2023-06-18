
// Copyright 2023 Ingonyama
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
	
// Code generated by Ingonyama DO NOT EDIT

#include <stdbool.h>
#include <cuda.h>
// ntt.h

#ifndef _BLS12381_NTT_H
#define _BLS12381_NTT_H

#ifdef __cplusplus
extern "C" {
#endif

// Incomplete declaration of BLS12381 projective and affine structs
typedef struct BLS12381_projective_t BLS12381_projective_t;
typedef struct BLS12381_affine_t BLS12381_affine_t;
typedef struct BLS12381_scalar_t BLS12381_scalar_t;

int ntt_cuda_bls12_381(BLS12381_scalar_t *arr, uint32_t n, bool inverse, size_t decimation, size_t device_id);
int ntt_batch_cuda_bls12_381(BLS12381_scalar_t *arr, uint32_t arr_size, uint32_t batch_size, bool inverse, size_t device_id);

int ecntt_cuda_bls12_381(BLS12381_projective_t *arr, uint32_t n, bool inverse, size_t device_id);
int ecntt_batch_cuda_bls12_381(BLS12381_projective_t *arr, uint32_t arr_size, uint32_t batch_size, bool inverse, size_t device_id);

#ifdef __cplusplus
}
#endif

#endif /* _BLS12381_NTT_H */
