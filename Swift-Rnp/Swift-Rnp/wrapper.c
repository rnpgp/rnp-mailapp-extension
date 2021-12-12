//
//  wrapper.c
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 23.11.2021.
//

#include "generate.h"
#include "decrypt.h"

int wHasKeys(const char *pub_format, const char *sec_format) {
    return ffi_has_keys(pub_format, sec_format);
}

int wCreateKeys(const char *pub_format, const char *sec_format) {
    return ffi_generate_keys(pub_format, sec_format);
}
