//
//  generate.h
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 24.11.2021.
//

#ifndef generate_h
#define generate_h

// TODO: Think about bool implementation
//typedef enum { false, true } bool;

int ffi_has_keys(const char *pub_format, const char *sec_format);
int ffi_generate_keys(const char *pub_format, const char *sec_format);
int ffi_output_keys(const char *pub_format, const char *sec_format);

#endif /* generate_h */
