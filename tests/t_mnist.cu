/** -*- c++ -*-
 * @File
 * @brief - tensorForth MNIST Dataset Loader
 *
 * <pre>Copyright (C) 2022- GreenII, this file is distributed under BSD 3-Clause License.</pre>
 */
#include "../src/vu/mnist_vu.h"
#include "../src/ldr/loader.h"

int main(int argc, char **argv) {
    setenv("DISPLAY", ":0", 0);
    cudaSetDevice(0);

    Loader::init();
    if (gui_init(&argc, argv)) return -1;
    
    Dataset *ds = Loader::get("mnist_train");
    if (ds) {
        MnistVu *vu = new MnistVu(*ds);
        gui_add(vu);
        
        return gui_loop();
    }
}

