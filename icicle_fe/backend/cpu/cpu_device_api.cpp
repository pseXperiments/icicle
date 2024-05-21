
#include <iostream>
#include <cstring>
#include "icicle/device_api.h"
#include "icicle/errors.h"

using namespace icicle;

class CPUDeviceAPI : public DeviceAPI
{
public:  
  // Memory management
  IcicleError allocateMemory(const Device& device, void** ptr, size_t size) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    *ptr = malloc(size);
    return (*ptr == nullptr) ? IcicleError::ALLOCATION_FAILED : IcicleError::SUCCESS;
  }

  IcicleError allocateMemoryAsync(const Device& device, void** ptr, size_t size, IcicleStreamHandle stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return CPUDeviceAPI::allocateMemory(device, ptr, size);
  }

  IcicleError freeMemory(const Device& device, void* ptr) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    free(ptr);
    return IcicleError::SUCCESS;
  }

  IcicleError freeMemoryAsync(const Device& device, void* ptr, IcicleStreamHandle stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return CPUDeviceAPI::freeMemory(device, ptr);
  }

  IcicleError getAvailableMemory(const Device& device, size_t& total /*OUT*/, size_t& free /*OUT*/) override
  {    
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    // TODO Yuval: implement this
    return IcicleError::API_NOT_IMPLEMENTED;
  }

  IcicleError memCopy(void* dst, const void* src, size_t size)
  {
    std::memcpy(dst, src, size);
    return IcicleError::SUCCESS;
  }

  // Data transfer
  IcicleError copyToHost(const Device& device, void* dst, const void* src, size_t size) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return memCopy(dst, src, size);
  }

  IcicleError
  copyToHostAsync(const Device& device, void* dst, const void* src, size_t size, IcicleStreamHandle stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return memCopy(dst, src, size);
  }

  IcicleError copyToDevice(const Device& device, void* dst, const void* src, size_t size) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return memCopy(dst, src, size);
  }

  IcicleError
  copyToDeviceAsync(const Device& device, void* dst, const void* src, size_t size, IcicleStreamHandle stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return memCopy(dst, src, size);
  }

  // Synchronization
  IcicleError synchronize(const Device& device, IcicleStreamHandle stream = nullptr) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return IcicleError::SUCCESS;
  }

  // Stream management
  IcicleError createStream(const Device& device, IcicleStreamHandle* stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    *stream = nullptr; // no streams for CPU
    return IcicleError::SUCCESS;
  }

  IcicleError destroyStream(const Device& device, IcicleStreamHandle stream) override
  {
    if (device.id != 0) return IcicleError::INVALID_DEVICE;
    return (nullptr == stream) ? IcicleError::SUCCESS : IcicleError::STREAM_DESTRUCTION_FAILED;
  }
};

REGISTER_DEVICE_API("CPU", CPUDeviceAPI);
