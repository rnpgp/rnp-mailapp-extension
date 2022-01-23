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

@property (nonatomic, strong) NSString *pub_format;
@property (nonatomic, strong) NSString *sec_format;

@property (nonatomic, assign) rnp_ffi_t ffi;

- (BOOL)checkIfHasKeys;
- (const char *)pubFormat;
- (const char *)secFormat;

@end

@implementation RnpObject

// MARK: - Private

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

- (BOOL)checkIfHasKeys {
    rnp_input_t keyfile = NULL;
    BOOL result = YES;
    
//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Wnon-literal-null-conversion"
//    const char *pubFilename = RnpConstantsPubFileName;
//#pragma clang diagnostic pop
    /* load keyrings */
    if (result && rnp_input_from_path(&keyfile, "pubring.pgp") != RNP_SUCCESS) {
        fprintf(stdout, "failed to open pubring file\n");
        result = NO;
    }
    
    /* actually, we may use 0 instead of RNP_LOAD_SAVE_PUBLIC_KEYS, to not check key types */
    if (result && rnp_load_keys(_ffi, self.pubFormat, keyfile, RNP_LOAD_SAVE_PUBLIC_KEYS) != RNP_SUCCESS) {
        fprintf(stdout, "failed to read pubring file\n");
        result = NO;
    }
    
    if (result) {
        rnp_input_destroy(keyfile);
        keyfile = NULL;
    }
    
//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Wnon-literal-null-conversion"
//    const char *secFilename = RnpConstantsSecFileName;
//#pragma clang diagnostic pop
    if (result && rnp_input_from_path(&keyfile, "secring.pgp") != RNP_SUCCESS) {
        fprintf(stdout, "failed to open secring file\n");
        result = NO;
    }
    
    if (result && rnp_load_keys(_ffi, self.secFormat, keyfile, RNP_LOAD_SAVE_SECRET_KEYS) != RNP_SUCCESS) {
        fprintf(stdout, "failed to read secring file\n");
        result = NO;
    }
    
    if (result) {
        rnp_input_destroy(keyfile);
    }
    
    return result;
}

- (const char *)pubFormat {
    return [_pub_format UTF8String];
}

- (const char *)secFormat {
    return [_sec_format UTF8String];
}

// MARK: - Public

- (instancetype)initWithPubFormat:(NSString *)pub_format secFormat:(NSString *)sec_format {
    self = [super init];
    if (self) {
        _pub_format = pub_format;
        _sec_format = sec_format;
    }
    
    if (rnp_ffi_create(&_ffi, self.pubFormat, self.secFormat) != RNP_SUCCESS) {
        return NULL;
    }
    
    _hasKeys = [self checkIfHasKeys];
    
    return self;
}

- (void)createKeys:(NSString *)userId password:(NSString *)password completion:(void (^)(BOOL)) completion {
    
    BOOL result = YES;
    
    // Set password and password provider
    [PrivateValueManager.shared setObject:password for:PrivateValueKeyPassword];
    if (result && rnp_ffi_set_pass_provider(_ffi, pass_provider , NULL) != RNP_SUCCESS) {
        fprintf(stdout, "failed to set pass provider\n");
        result = NO;
    }
    
    char * key_grips = NULL;
    // generate EDDSA/X25519 keypair
    const char *json = [[KeyDescriptionGenerator curve25519KeyWithUserId:userId expiration:KeyExpirationHalfYear] UTF8String];
    if (result && rnp_generate_key_json(_ffi, json, &key_grips) != RNP_SUCCESS) {
        fprintf(stdout, "failed to generate key json\n");
        result = NO;
    }
    
    if (result) {
        fprintf(stdout, "Generated 25519 key/subkey:\n%s\n", key_grips);
        /* destroying key_grips buffer is our obligation */
        rnp_buffer_destroy(key_grips);
        key_grips = NULL;
        json = NULL;
    }
    
    // generate RSA keypair
    json = [[KeyDescriptionGenerator rsaKeyWithUserId:userId expiration:KeyExpirationHalfYear] UTF8String];
    if (result && rnp_generate_key_json(_ffi, json, &key_grips) != RNP_SUCCESS) {
        fprintf(stdout, "failed to generate rsa key\n");
        result = NO;
    }
    
    if (result) {
        fprintf(stdout, "Generated RSA key/subkey:\n%s\n", key_grips);
        rnp_buffer_destroy(key_grips);
        key_grips = NULL;
    }
    [PrivateValueManager.shared clearObjectFor:PrivateValueKeyPassword];
    
    // pubring
    rnp_output_t keyfile = NULL;
    if (result && rnp_output_to_path(&keyfile, "pubring.pgp") != RNP_SUCCESS) {
        fprintf(stdout, "failed to initialize pubring.pgp writing\n");
        result = NO;
    }
    
    if (result && rnp_save_keys(_ffi, self.pubFormat, keyfile, RNP_LOAD_SAVE_PUBLIC_KEYS) != RNP_SUCCESS) {
        fprintf(stdout, "failed to save pubring\n");
        result = NO;
    }
    
    if (result) {
        rnp_output_destroy(keyfile);
        keyfile = NULL;
    }
    
    // secring
    if (result && rnp_output_to_path(&keyfile, "secring.pgp") != RNP_SUCCESS) {
        fprintf(stdout, "failed to initialize secring.pgp writing\n");
        result = NO;
    }
    
    if (result && rnp_save_keys(_ffi, self.secFormat, keyfile, RNP_LOAD_SAVE_SECRET_KEYS) != RNP_SUCCESS) {
        fprintf(stdout, "failed to save secring\n");
        result = NO;
    }
    
    if (result) {
        rnp_output_destroy(keyfile);
        keyfile = NULL;
    }
    
    rnp_buffer_destroy(key_grips);
    rnp_output_destroy(keyfile);
    
    _hasKeys = [self checkIfHasKeys];
    
    completion(result);
}

@end
