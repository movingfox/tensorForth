/**
 * @file
 * @brief tensorForth tensor class implementation
 *
 * <pre>Copyright (C) 2022- GreenII, this file is distributed under BSD 3-Clause License.</pre>
 */
#include "tensor.h"
__KERN__ void k_matrix_randomize(DU *mat, int nrow, int ncol, int seed=0)
{
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    int j = threadIdx.y + blockIdx.y * blockDim.y;

    if (i < ncol && j < nrow) {
        int off = i + j * ncol;      /* row major */

        // Generate arbitrary elements.
        int const k = 16807;
        int const m = 16;
        DU v = DU(((off + seed) * k % m) - m / 2);

        mat[off] = v;
    }
}

__HOST__
Tensor::Tensor() :
    dsize(sizeof(DU)),
    size(0),
    rank(0),
    stride{0, 0, 0, 0},
    shape{0, 0, 0, 0} {}

__HOST__
Tensor::Tensor(U64 sz) :
    dsize(sizeof(DU)),
    size(sz),
    rank(1),
    stride{0, 0, 0, 0},
    shape{0, 0, 0, 0} {
    cudaMallocManaged((void**)&data, size);
    GPU_CHK();
    printf("tensor[%ld] allocated\n", size);
}

__HOST__
Tensor::Tensor(U16 h, U16 w) :
    dsize(sizeof(DU)),
    size(dsize * h * w),
    rank(2),
    stride{1, 1, 0, 0},
    shape{h, w, 0, 0} {
    cudaMallocManaged((void**)&data, (size_t)size);
    GPU_CHK();
    printf("matrix(%d,%d) allocated\n", shape[0], shape[1]);
}

__HOST__
Tensor::Tensor(U16 n, U16 h, U16 w, U16 c) :
    dsize(sizeof(DU)),
    size(dsize * n * h * w * c),
    rank(4),
    stride{1, 1, 1, 1},
    shape{h, w, n, c} {
    cudaMallocManaged((void**)&data, (size_t)size);
    GPU_CHK();
    printf("tensor(%d,%d,%d,%d) allocated\n", shape[2], shape[0], shape[1], shape[3]);
}

__HOST__
Tensor::~Tensor()
{
    if (!data) return;
    cudaFree((void*)data);
    switch (rank) {
    case 2: printf("matrix(%d,%d) freed\n", shape[0], shape[1]); break;
    case 4: printf("tensor(%d,%d,%d,%d) freed\n", shape[2], shape[0], shape[1], shape[3]); break;
    default: printf("~Tensor error: rank=%d\n", rank);
    }
}

__BOTH__ Tensor&
Tensor::reset(void *mptr, U64 sz) {
    dsize  = sizeof(DU);
    size   = sz;
    rank   = 1;
    memset(stride, 0, sizeof(U16) * 4);
    memset(shape,  0, sizeof(U16) * 4);
    data   = (U8*)mptr;
    printf("tensor reset(%p, %ld)\n", mptr, sz);
    return *this;
}

__BOTH__ Tensor&
Tensor::reshape(U16 h, U16 w) {
    U64 sz = dsize * h * w;
    if (sz == size) {
        rank   = 2;
        U16 t[4] = {1, 1, 0, 0}; memcpy(stride, t, sizeof(t));
        U16 s[4] = {h, w, 0, 0}; memcpy(shape,  s, sizeof(s));
        printf("tensor reshaped(%d,%d)\n", shape[0], shape[1]);
    }
    else {
        printf("reshape sz != size (%ld != %ld)\n", sz, size);
    }
    return *this;
}

__BOTH__ Tensor&
Tensor::reshape(U16 n, U16 h, U16 w, U16 c) {
    U64 sz = dsize * n * h * w * c;
    if (sz == size) {
        rank   = 4;
        U16 t[4] = {1, 1, 1, 1}; memcpy(stride, t, sizeof(t));
        U16 s[4] = {h, w, n, c}; memcpy(shape,  s, sizeof(s));
        printf("tensor reshaped(%d,%d,%d,%d)\n", shape[2], shape[0], shape[1], shape[3]);
    }
    else {
        printf("reshape sz != size (%ld != %ld)\n", sz, size);
    }
    return *this;
}

__BOTH__ Tensor&
Tensor::fill(DU v) {
    U32 sz = size / dsize;
    DU  *d = (DU*)data;
    for (int i=0; i<sz; i++) *d++ = v;
    return *this;
}

__BOTH__ Tensor&
Tensor::random(int seed) {
    int h = H();
    int w = W();
    dim3 block(16, 16);
    dim3 grid(
        (w + block.x - 1) / block.x,     /* row major */
        (h + block.y - 1) / block.y
        );
    k_matrix_randomize<<<grid, block>>>((DU*)data, h, w, seed);
    return *this;
}
