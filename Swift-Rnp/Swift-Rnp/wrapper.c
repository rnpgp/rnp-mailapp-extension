//
//  wrapper.c
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 23.11.2021.
//

#include "generate.h"
#include <stdio.h>

int ffi_generate(void) {
    int res = ffi_generate_keys();
    return res;
}

    //int
    //main(int argc, char **argv)
    //{
    //    int res = ffi_generate_keys();
    //    if (res) {
    //        return res;
    //    }
    //    res = ffi_output_keys();
    //    return res;
    //}
