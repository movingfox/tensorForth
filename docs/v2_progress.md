# tensorForth - Release 2.0 / 2022-07
## Features
* array, matrix objects (modeled to PyTorch)
* TLSF tensor storage manager
* matrix arithmetics (i.e. +, -, *, copy, mm, transpose)
* matrix init (i.e. zeros, ones, full, eye, random)
* GEMM (i.e. a * A x B + b * C, use CUDA Dynamic Parallelism)
* tensor view instead of deep copy (i.e. dup, over, pick, r@, )
* matrix print (i.e PyTorch-style, adjustable edge elements)
* matrix console input (i.e. matrix[..., array[..., and T![)
* command line option: debug print level control (MMU_DEBUG)
* command line option: list (all) device properties

## tensorForth Command line options
* - -h - list all GPU id and their properties<br/>
Example:> ./ten4 - -h<br/>
<pre>
CUDA Device #0
    Name:                          NVIDIA GeForce GTX 1660
	CUDA version:                  7.5
	Total global memory:           5939M
	Total shared memory per block: 48K
	Number of multiprocessors:     22
	Total registers per block:     64K
	Warp size:                     32
	Max memory pitch:              2048M
	Max threads per block:         1024
	Max dim of block:              [1024, 1024, 64]
	Max dim of grid:               [2048M, 64K, 64K]
	Clock rate:                    1800KHz
	Total constant memory:         64K
	Texture alignment:             512
	Concurrent copy and execution: Yes
	Kernel execution timeout:      Yes
</pre>
* - -d - enter device id
Example:> ./ten4 - -d=0
<pre>
tensorForth 2.0
VM[0] dict=0x7fe3d2000a00, mem=0x7fe3d2004a00, vss=0x7fe3d2010a00
GPU 0 initialized at 1800MHz, dict[1024], pmem=48K, tensor=1024M
</pre>

## Forth Tensor operations
### Tensor creation ops
|word|param|tensor creation ops|
|---|---|---|
|array|(n -- T1)|create a 1-D array and place on top of stack (TOS)|
||> 5 array|T1[5]|
|matrix|(h w -- T2)|create 2-D matrix and place on TOS|
||> 2 3 matrix|T2[2,3]|
|tensor|(n h w c -- T4)|create a 4-D NHWC tensor on TOS|
||> 1 18 18 8 tensor|T4[1,18,18,8]|
|array[|(n -- T1)|create 1-D array from console stream|
||> 5 array[ 1 2 3 4 5 ]|T1[5]|
|matrix[|(h w -- T2)|create a 2-D matrix as TOS|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> 3 2 matrix[ [ 1 2 ] [ 3 4 ] [ 5 6 ] ]|T2[2,3] T[3,2]|
|copy|(Ta -- Ta Ta')|duplicate (deep copy) a tensor on TOS|
||> 2 3 matrix|T2[2,3]|
||> copy|T2[2,3] T2[2,3]|
### Views creation ops
|word|param|view creation ops|
|---|---|---|
|dup|(Ta -- Ta Ta')|create a view of a tensor on TOS|
||> 2 3 matry [ 1 2 3 4 5 6 ]|T2[2,3]|
||> dup|T2[2,3] V2[2,3]|
|over|(Ta Tb -- Ta Tb Ta')||
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> 3 2 matrix|T2[2,3] T2[3,2]|
||> over|T2[2,3] T2[3,2] V2[2,3]|
|2dup|(Ta Tb -- Ta Tb Ta' Tb')||
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> 3 2 matrix|T2[2,3] T2[3,2]|
||> 2dup|T2[2,3] T2[3,2] V2[2,3] V2[3,2]|
|2over|(Ta Tb Tc Td -- Ta Tb Tc Td Ta' Tb')||
### Tensor/View print
|word|param|Tensor/View print|
|---|---|---|
|. (dot)|(T1 -- )|print array|
||> 5 array[ 1 2 3 4 5]|T1[5]|
||> .|`array[+1.0000, +2.0000, +3.0000, +4.0000, +5.0000]`|
|. (dot)|(T2 -- )|print matrix|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> .|`matrix[`<br/>`[+1.0000, +2.0000, +3.0000],`<br/>`  [+4.0000, +5.0000, +6.0000]]`|
|. (dot)|(V2 -- )|print view|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> dup|T2[2,3] V2[2,3]|
||> .|`matrix[`<br/>`[+1.0000, +2.0000, +3.0000],`<br/>`  [+4.0000, +5.0000, +6.0000]]`|
### Shape ops
|word|param|Shape ops|
|---|---|---|
|flatten|(Ta -- Ta')|reshap a tensor to 1-D array|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> flatten|T1[6]|
||> .|`array[+1.0000, +2.0000, +3.0000, +4.0000, +5.0000, +6.0000]`|
|reshape2|(a b Ta -- Ta')|reshape a 2-D matrix|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> 3 2 reshape2|T2[3,2]|
|reshape4||reshape to a 4-D NHWC tensor|
||> 2 3 matrix[ 1 2 3 4 5 6 ]|T2[2,3]|
||> 1 3 2 1 reshape4|T4[1,3,2,1]|
### Fill ops
|word|param|Fill tensor with init valuess|
|---|---|---|
|T![|(Ta -- Ta)|fill tensor with console input|
||> 2 3 matrix|T2[2,3]|
||> T![ 1 2 3 4 5 6 ]|T2[2,3]|
|zeros|(Ta -- Ta')|fill tensor with zeros|
|ones|(Ta -- Ta')|fill tensor with ones|
|full|(Ta n -- Ta')|fill tensor with number on TOS|
|eye|(Ta -- Ta')|fill diag with 1 and other with 0|
|random|(Ta -- Ta')|fill tensor with random numbers|
### Matrix ops
|word|param|Matrix arithmetic ops|
|---|---|---|
|+|(Ta Tb -- Ta Tb Tc)|tensor element-wise addition|
|-|(Ta Tb -- Ta Tb Tc)|tensor element-wise subtraction|
|*|(Ta Tb -- Ta Tb Tc)|matrix multiplication|
|/|(Ta Tb -- Ta Tb Tc)|A * inv(B) matrix|
|inv|(Ta -- Ta)|TODO|
|trans|(Ta -- Ta Tat)|matrix transpose|
|mm|(Ta Tb -- Ta Tb Tc)|matrix multiplication|
|gemm|(a b Ta Tb Tc -- a b Ta Tb Tc Tc')|GEMM Tc' = a * Ta x Tb + b * Tc|
