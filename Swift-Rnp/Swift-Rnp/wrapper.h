//
//  wrapper.h
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 23.11.2021.
//

#ifndef wrapper_h
#define wrapper_h

int wHasKeys(const char *pub_format, const char *sec_format);
int wCreateKeys(const char *pub_format, const char *sec_format);

int wDecrypt(const char *pub_format, const char *sec_format, int usekeys);

#endif /* wrapper_h */
