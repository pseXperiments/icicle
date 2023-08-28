#pragma once

#include "field.cuh"

template <class FF>
class Affine
{
public:
  FF x;
  FF y;

  static HOST_DEVICE_INLINE Affine neg(const Affine& point) { return {point.x, FF::neg(point.y)}; }

  friend HOST_DEVICE_INLINE bool operator==(const Affine& xs, const Affine& ys)
  {
    return (xs.x == ys.x) && (xs.y == ys.y);
  }

  friend HOST_INLINE std::ostream& operator<<(std::ostream& os, const Affine& point)
  {
    os << "x: " << point.x << "; y: " << point.y;
    return os;
  }
};
