#pragma once

#include <stdexcept>
#include <iostream>

namespace icicle {

  /**
   * @brief Enum representing various error codes for Icicle library operations.
   */
  enum class eIcicleError {
    SUCCESS = 0,               ///< Operation completed successfully
    INVALID_DEVICE,            ///< The specified device is invalid
    OUT_OF_MEMORY,             ///< Memory allocation failed due to insufficient memory
    INVALID_POINTER,           ///< The specified pointer is invalid
    ALLOCATION_FAILED,         ///< Memory allocation failed
    DEALLOCATION_FAILED,       ///< Memory deallocation failed
    COPY_FAILED,               ///< Data copy operation failed
    SYNCHRONIZATION_FAILED,    ///< Device synchronization failed
    STREAM_CREATION_FAILED,    ///< Stream creation failed
    STREAM_DESTRUCTION_FAILED, ///< Stream destruction failed
    API_NOT_IMPLEMENTED,       ///< The API is not implemented for a device
    INVALID_ARGUMENT,          ///< Invalid argument passed
    UNKNOWN_ERROR              ///< An unknown error occurred
  };

  /**
   * @brief Returns a human-readable string representation of an eIcicleError.
   *
   * @param error The eIcicleError to get the string representation for.
   * @return const char* A string describing the error.
   */
  const char* getErrorString(eIcicleError error);

#define ICICLE_CHECK(api_call)                                                                                         \
  do {                                                                                                                 \
    using namespace icicle;                                                                                            \
    eIcicleError rv = (api_call);                                                                                      \
    if (rv != eIcicleError::SUCCESS) {                                                                                 \
      throw std::runtime_error(                                                                                        \
        "Icicle API fails with code " + std::string(getErrorString(rv)) + " in " + __FILE__ + ":" +                    \
        std::to_string(__LINE__));                                                                                     \
    }                                                                                                                  \
  } while (0)

  void inline throwIcicleErr(
    eIcicleError err, const char* const reason, const char* const func, const char* const file, const int line)
  {
    std::string err_msg = std::string{getErrorString(err)} + " : by: " + func + " at: " + file + ":" +
                          std::to_string(line) + " error: " + reason;
    std::cerr << err_msg << std::endl; // TODO: Logging
    throw std::runtime_error(err_msg);
  }

#define THROW_ICICLE_ERR(val, reason) throwIcicleErr(val, reason, __FUNCTION__, __FILE__, __LINE__)

} // namespace icicle
