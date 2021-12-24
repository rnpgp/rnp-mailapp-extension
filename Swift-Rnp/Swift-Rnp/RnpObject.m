//
//  RnpObject.m
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 19.12.2021.
//

#import "RnpObject.h"
#import "rnp_err.h"
#import "Swift_Rnp-Swift.h"

#define kUDPassKey @"kPassword"

@interface RnpObject ()

@property (nonatomic, assign) const char *pub_format;
@property (nonatomic, assign) const char *sec_format;

@property (nonatomic, strong) NSString *password;

@end

@implementation RnpObject

// Class binded completion
bool pass_provider(rnp_ffi_t        ffi,
                   void *           app_ctx,
                   rnp_key_handle_t key,
                   const char *     pgp_context,
                   char             buf[],
                   size_t           buf_len)
{
    if (strcmp(pgp_context, "protect")) {
        return false;
    }
    
    const char* password = [[PrivateValueManager.shared objectFor: PrivateValueKeyPassword] UTF8String];
    if (!password || strlen(password) == 0) {
        return false;
    }
    
    strncpy(buf, password, buf_len);
    return true;
}

const char *CURVE_25519_KEY_DESC_2 = "{\
    'primary': {\
        'type': 'EDDSA',\
        'userid': 'sergeyvinogradov@icloud.com',\
        'expiration': 0,\
        'usage': ['sign'],\
        'protection': {\
            'cipher': 'AES256',\
            'hash': 'SHA256'\
        }\
    },\
    'sub': {\
        'type': 'ECDH',\
        'curve': 'Curve25519',\
        'expiration': 15768000,\
        'usage': ['encrypt'],\
        'protection': {\
            'cipher': 'AES256',\
            'hash': 'SHA256'\
        }\
    }\
}";

- (instancetype)initWithPubFormat:(const char *)pub_format secFormat:(const char *)sec_format {
    self = [super init];
    if (self) {
        _pub_format = pub_format;
        _sec_format = sec_format;
    }
    
    rnp_ffi_t ffi = NULL;
    rnp_result_t res = rnp_ffi_create(&ffi, pub_format, sec_format);
    
    // Set password and password provider
    [PrivateValueManager.shared setObject:@"aPassword" for:PrivateValueKeyPassword];
    rnp_result_t res2 = rnp_ffi_set_pass_provider(ffi, pass_provider , NULL);
    [PrivateValueManager.shared clearObjectFor:PrivateValueKeyPassword];
    
    char *       key_grips = NULL;
    rnp_result_t res3 = rnp_generate_key_json(ffi, CURVE_25519_KEY_DESC_2, &key_grips);
    
    return self;
}

@end
