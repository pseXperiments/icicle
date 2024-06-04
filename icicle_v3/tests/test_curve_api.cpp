
#include <gtest/gtest.h>
#include <iostream>
#include "dlfcn.h"

#include "icicle/runtime.h"
#include "icicle/msm.h"
#include "icicle/vec_ops.h"
#include "icicle/curves/curve_config.h"

using namespace curve_config;
using namespace icicle;

using FpMicroseconds = std::chrono::duration<float, std::chrono::microseconds::period>;
#define START_TIMER(timer) auto timer##_start = std::chrono::high_resolution_clock::now();
#define END_TIMER(timer, msg, enable)                                                                                  \
  if (enable)                                                                                                          \
    printf(                                                                                                            \
      "%s: %.3f ms\n", msg, FpMicroseconds(std::chrono::high_resolution_clock::now() - timer##_start).count() / 1000);

static bool VERBOSE = true;

class CurveApiTest : public ::testing::Test
{
public:
  static inline std::list<std::string> s_regsitered_devices;

  // SetUpTestSuite/TearDownTestSuite are called once for the entire test suite
  static void SetUpTestSuite()
  {
    icicle_load_backend(BACKEND_BUILD_DIR);
    s_regsitered_devices = get_registered_devices();
    ASSERT_GT(s_regsitered_devices.size(), 0);
  }
  static void TearDownTestSuite() {}

  // SetUp/TearDown are called before and after each test
  void SetUp() override {}
  void TearDown() override {}
};

TEST_F(CurveApiTest, MSM)
{
  const int logn = 5;
  const int N = 1 << logn;
  auto scalars = std::make_unique<scalar_t[]>(N);
  auto bases = std::make_unique<affine_t[]>(N);

  scalar_t::rand_host_many(scalars.get(), N);
  projective_t::rand_host_many_affine(bases.get(), N);

  projective_t result{};

  auto run = [&](const char* dev_type, projective_t* result, const char* msg, bool measure, int iters) {
    Device dev = {dev_type, 0};
    icicle_set_device(dev);

    auto config = default_msm_config();

    START_TIMER(MSM_sync)
    for (int i = 0; i < iters; ++i) {
      // TODO real test
      msm_precompute_bases(bases.get(), N, 1, default_msm_pre_compute_config(), bases.get());
      msm(scalars.get(), bases.get(), N, config, result);
    }
    END_TIMER(MSM_sync, msg, measure);
  };

  run("CPU", &result, "CPU msm", VERBOSE /*=measure*/, 1 /*=iters*/);
  // TODO test something
}

int main(int argc, char** argv)
{
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}