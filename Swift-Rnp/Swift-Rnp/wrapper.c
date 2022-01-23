//
//  wrapper.c
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 23.11.2021.
//

#include "decrypt.h"

int wDecrypt(const char *pub_format, const char *sec_format, int usekeys) {
    return ffi_decrypt(pub_format, sec_format, usekeys);
}
