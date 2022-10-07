/** -*- c++ -*-
 * @file
 * @brief Model class - Neural Network model constructor implementation
 *
 * <pre>Copyright (C) 2022- GreenII, this file is distributed under BSD 3-Clause License.</pre>
 */
#include "model.h"

#if T4_ENABLE_OBJ
__HOST__ const char*
Model::nname(int i) {               ///< network layer name
    static const char *name[] = {   /// double check with t4_layer
    "output ", "conv2d ", "linear ", "flatten", "relu   ",
    "tanh   ", "sigmoid", "softmax", "logsmax", "maxpool",
    "avgpool", "minpool", "dropout"
    };
    return name[i];
}
__GPU__ const char*
Model::d_nname(int i) {
    static const char* name[] = {   /// double check with t4_layer
    "output ", "conv2d ", "linear ", "flatten", "relu   ",
    "tanh   ", "sigmoid", "softmax", "logsmax", "maxpool",
    "avgpool", "minpool", "dropout"
    };
    return name[i];
}
///
/// NN layer factory
///
__GPU__ Model&
Model::add(t4_layer fn, U16 n, DU bias, U16 *opt) {
    Tensor &in = (*this)[-1];
    if (!autograd || in.grad_fn != L_NONE) return *this;
    
    switch(fn) {
    case L_CONV:    _iconv(in, n, bias, opt);   break;
    case L_LINEAR:  _ilinear(in, n, bias);      break;
    case L_FLATTEN: _iflatten(in);              break;
    case L_RELU:
    case L_TANH:
    case L_SIGMOID: _icopy(in);                 break;
    case L_SOFTMAX:
    case L_LOGSMAX: _isoftmax(in);              break;
    case L_MAXPOOL:
    case L_AVGPOOL:
    case L_MINPOOL: _ipool(in, n);              break;
    case L_DROPOUT: _idropout(in, n);           break;
    default: ERROR("Model#add layer %d not supported\n", fn);
    }
    in.grad_fn = fn;

    int C0 = (*this)[-1].C();
    if (C0 * T4_WARP_SQ > 1024) {
        ERROR("Model#add out.C=%d => over CUDA 1024 thread per core\n", C0);
    }
    return *this;
}
///
/// Convolution and Linear ops
///
__GPU__ void
Model::_iconv(Tensor &in, U16 C0, DU bias, U16 *opt) {
    U16 N1 = in.N(), C1 = in.C();                 ///> batch_sz, channels
    U16 Hf = opt[0], Wf = opt[1];                 ///> filter sizing
    U16 p  = opt[2] ? opt[2] : int((Hf-1)/2);     ///> padding
    U16 s  = opt[3], d = opt[4];                  ///> stride, dilation
    U16 H0 = (in.H() - Hf + p*2) / s + 1;         ///> output height
    U16 W0 = (in.W() - Wf + p*2) / s + 1;         ///> output width
    if (Hf != Wf || (Hf != 3 && Hf != 5)) {
        ERROR("Model#conv2d f=[%d,%d]? 3x3 and 5x5 supported only.\n", Hf, Wf);
        return;
    }
    in.stride[0] = in.stride[1] = s;
    ///
    /// filter: C1 to C0 fully connected
    /// TODO: filters's 5th dimension is stored in parm field for now
    ///
    Tensor *f  = in.grad[0] = &_t5(C1, N1, Hf, Wf, C0);                  ///> f
    Tensor *df = in.grad[2] = &_t5(C1, N1, Hf, Wf, C0).map(O_FILL, DU0); ///> df
    Tensor *b  = in.grad[1] = &_vec(C0).map(O_FILL, bias);               ///> b
    Tensor *db = in.grad[3] = &_vec(C0).map(O_FILL, DU0);                ///> db

    DU k = DU1 / SQRT(Hf * Wf * C1);             /// * filter default range
    _mmu->random(*f, UNIFORM, -0.5, 2.0 * k);    /// * randomize f [-k ~ k)
    /*
    printf("bias=%4.2f,  k=%6.4f, f.std=%6.4f\n", bias, k, f->std());
    for (int i=0; i<f->numel; i++) {
        DU dx = f->data[i];
        printf("%6.3f", dx);
    }
    */
    Tensor &out= _t4(N1, H0, W0, C0);           ///> output tensor
    npush(out);                                 /// * stage for next stage
}
__GPU__ void
Model::_ilinear(Tensor &in, U16 C0, DU bias) {
    U16 N1 = in.N(), C1 = in.HWC();
    Tensor *w  = in.grad[0] = &_t4(1, C0, C1, 1);                   ///> w
    Tensor *dw = in.grad[2] = &_t4(1, C0, C1, 1).map(O_FILL, DU0);  ///> dw
    Tensor *b  = in.grad[1] = &_vec(C0).map(O_FILL, bias);          ///> b
    Tensor *db = in.grad[3] = &_vec(C0).map(O_FILL, DU0);           ///> db
    
    DU k = DU1 / SQRT(C1);                       /// * default weight
    _mmu->random(*w, UNIFORM, -0.5, 2.0 * k);    /// * randomize w
    printf("bias=%4.2f,  k=%6.3f, w.std=%6.3f\n", bias, k, w->std());
    
    Tensor &out = _t4(N1, C0);                   ///> output tensor sizing
    printf(" out[%d,%d,%d,%d]", out.N(), out.H(), out.W(), out.C());
    npush(out);                                  /// * stage for next stage
}
__GPU__ void
Model::_iflatten(Tensor &in) {
    in.parm = in.HWC();                          /// * keep numel per sample
    printf("flatten parm=%d\n", in.parm);
    Tensor &out = _t4(in.N(), in.parm);          /// * for backprop
    npush(out);
}
///
/// Activation ops
///
__GPU__ void
Model::_icopy(Tensor &in) {
    Tensor &out = _mmu->copy(in);                ///> output tensor sizing
    npush(out);                                  /// * stage for next stage
}

__GPU__ void
Model::_isoftmax(Tensor &in) {
    Tensor *sum = in.grad[0] = &_vec(in.N());    ///> for sum per sample
    Tensor &out = _mmu->copy(in);                ///> output tensor sizing
    npush(out);
}
///
/// Pooling and Dropout ops
///
__GPU__ void
Model::_ipool(Tensor &in, U16 f) {
    if (f != 2 && f != 3) {
        ERROR("Model#pooling f=[%d,%d]? 2x2 and 3x3 supported only\n", f, f);
        return;
    }
    in.parm = f;                                 /// * keep kernel size
                                                 /// * used by backprop
    U16 H0 = int((in.H() - f) / f) + 1;
    U16 W0 = int((in.W() - f) / f) + 1;
    U16 s[4] = { f, f, 1, 1 }; memcpy(in.stride, s, sizeof(s));  // stride
    
    Tensor &out = _t4(in.N(), H0, W0, in.C());
    npush(out);                                  /// * stage for next stage
}

__GPU__ void
Model::_idropout(Tensor &in, U16 f) {
    Tensor &out = _mmu->copy(in);
    Tensor *msk = in.grad[0] = &_mmu->copy(in);  ///> dropout mask
    
    in.parm = f;                                 /// * keep fraction
    DU p = -0.01 * f;                            ///< dropout fraction
    _mmu->random(*msk, UNIFORM, p);              /// * randomize w, shift p
    printf("dropout=%d\n", f);
    
    npush(out);
}
#endif  // T4_ENABLE_OBJ
//==========================================================================
