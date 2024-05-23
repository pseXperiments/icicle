
#include "icicle/vec_ops/vec_ops.h"
#include "icicle/errors.h"
#include "icicle/runtime.h"

#include "fields/field_config.h"

using namespace field_config;
using namespace icicle;

eIcicleError CpuVectorAdd(
  const Device& device,
  const scalar_t* vec_a,
  const scalar_t* vec_b,
  int n,
  const VecOpsConfig& config,
  scalar_t* output)
{
  for (int i = 0; i < n; ++i) {
    output[i] = vec_a[i] + vec_b[i];
  }
  return eIcicleError::SUCCESS;
}

REGISTER_VECTOR_ADD_BACKEND("CPU", CpuVectorAdd);