/**
 * @file
 * @brief tensorForth tensor class
 *
 * <pre>Copyright (C) 2022- GreenII, this file is distributed under BSD 3-Clause License.</pre>
 */
#ifndef TEN4_SRC_TENSOR_H_
#define TEN4_SRC_TENSOR_H_
#include "ten4_types.h"
#include "vector.h"
/**
  TODO: Matrix product of two Tensors.
  The behavior depends on the dimensionality of the Tensors as follows:
  - If both Tensors are 1-dimensional, the dot product (scalar) is returned.
  - If both arguments are 2-dimensional, the matrix-matrix product is returned.
  - If the first argument is 1-dimensional and the second argument is 2-dimensional,
    a 1 is prepended to its dimension for the purpose of the matrix multiply.
    After the matrix multiply, the prepended dimension is removed.
  - If the first argument is 2-dimensional and the second argument is 1-dimensional,
    the matrix-vector product is returned.
  - If both arguments are at least 1-dimensional and at least one argument is
    N-dimensional (where N > 2), then a batched matrix multiply is returned.  If the first
    argument is 1-dimensional, a 1 is prepended to its dimension for the purpose of the
    batched matrix multiply and removed after.  If the second argument is 1-dimensional, a
    1 is appended to its dimension for the purpose of the batched matrix multiple and removed after.
    The non-matrix (i.e. batch) dimensions are broadcasted (and thus
    must be broadcastable).  For example, if tensor1 is a (j x 1 x n x m) Tensor
    and tensor2 is a (k x m x p) Tensor, the returned tensor will be an (j x k x n x p) Tensor.
*/
//===============================================================================
/// tensorForth tensor class
///@}
///@name tensorForth complex data object
///@{
struct TensorStore : public Managed {
    U64 offset;                ///< offset to managed memory pool
    U64 size;                  ///< number of contiguous bytes
};
/*
 * PyTorch.Tensor: size, dtype, type_id, stride, tensorstore
 */
struct Tensor : public Managed {
    U64              size;     ///< number of contiguous bytes
    U32              dsize;    ///< size of data element, F32 for now, TODO: others
    Vector<U16,4>    stride;   ///< one step forward (row major)
    Vector<U16,4>    shape;    ///< shape of the tensor, max 4-T for now. TODO: more
    TensorStore      *data;    ///< pointer to Managed memory
    union {
        DU f;               ///< float storage
        struct {
            U32 t  : 1;     ///< tensor rank >= 1
            U32 idx: 31;    ///< tensor pool index (2^31 slots)
        };
    };
    __BOTH__ Tensor()     : f(DU0) { t = 0; }
    __BOTH__ Tensor(DU f0): f(f0)  { t = 0; }
    __BOTH__ __INLINE__ Tensor &operator=(DU f0) { f = f0; t = 0; return *this; }
    ///
    /// tensor arithmetics
    ///
    __BOTH__ __INLINE__ Tensor &operator+=(Tensor &t){ f += t.f; return *this; }
    __BOTH__ __INLINE__ Tensor &operator-=(Tensor &t){ f -= t.f; return *this; }
    __BOTH__ __INLINE__ F32    operator+(Tensor &t)  { return f + t.f; }
    __BOTH__ __INLINE__ F32    operator-(Tensor &t)  { return f - t.f; }
    __BOTH__ __INLINE__ F32    operator*(Tensor &t)  { return f * t.f; }
    __BOTH__ __INLINE__ F32    operator/(Tensor &t)  { return f / t.f; }
    __BOTH__ __INLINE__ F32    operator%(Tensor &t)  { return fmod(f, t.f); }
    ///
    /// tensor logical ops
    ///
    __BOTH__ __INLINE__ bool   operator<(Tensor &t)  { return (f - t.f) <  -DU_EPS; }
    __BOTH__ __INLINE__ bool   operator>(Tensor &t)  { return (f - t.f) >   DU_EPS; }
    __BOTH__ __INLINE__ bool   operator<=(Tensor &t) { return (f - t.f) <= -DU_EPS; }
    __BOTH__ __INLINE__ bool   operator>=(Tensor &t) { return (f - t.f) >=  DU_EPS; }
    __BOTH__ __INLINE__ bool   operator==(Tensor &t) { return fabs(f - t.f) <  DU_EPS; }
    __BOTH__ __INLINE__ bool   operator!=(Tensor &t) { return fabs(f - t.f) >= DU_EPS; }
    ///
    /// float arithmetics
    ///
    __BOTH__ __INLINE__ Tensor &operator+=(F32 f0)   { f += f0; t = 0; return *this; }
    __BOTH__ __INLINE__ Tensor &operator-=(F32 f0)   { f -= f0; t = 0; return *this; }
    __BOTH__ __INLINE__ Tensor &operator*=(F32 f0)   { f *= f0; t = 0; return *this; }
    __BOTH__ __INLINE__ Tensor &operator/=(F32 f0)   { f /= f0; t = 0; return *this; }
    ///
    /// float logical ops
    ///
    __BOTH__ __INLINE__ bool   operator<(F32 f0)     { return (f - f0) <  -DU_EPS; }
    __BOTH__ __INLINE__ bool   operator>(F32 f0)     { return (f - f0) >   DU_EPS; }
    __BOTH__ __INLINE__ bool   operator>=(F32 f0)    { return (f - f0) >=  DU_EPS; }
    __BOTH__ __INLINE__ bool   operator==(F32 f0)    { return fabs(f - f0)  <  DU_EPS; }
    __BOTH__ __INLINE__ bool   operator!=(F32 f0)    { return fabs(f - f0)  >= DU_EPS; }
    ///
    /// GEMM ops
    ///
    __GPU__ Tensor &gemm(Tensor &A, Tensor &B, Tensor &C);
};
#endif // TEN4_SRC_TENSOR_H_