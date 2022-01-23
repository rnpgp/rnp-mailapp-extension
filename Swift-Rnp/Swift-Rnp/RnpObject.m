//
//  RnpObject.m
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 19.12.2021.
//

#import "RnpObject.h"
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
bool generate_pass_provider(rnp_ffi_t        ffi,
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

bool decrypt_pass_provider(rnp_ffi_t        ffi,
                           void *           app_ctx,
                           rnp_key_handle_t key,
                           const char *     pgp_context,
                           char             buf[],
                           size_t           buf_len)
{
    const char* password = [[PrivateValueManager.shared objectFor: PrivateValueKeyPassword] UTF8String];
    if (!password || strlen(password) == 0) {
        return false;
    }
    
    if (!strcmp(pgp_context, "decrypt (symmetric)")) {
        strncpy(buf, password, buf_len);
        return true;
    }
    if (!strcmp(pgp_context, "decrypt")) {
        strncpy(buf, password, buf_len);
        return true;
    }
    
    return false;
}

// TODO: Keypairs should contain some info about UserId. Can be saved separatelly in keychain, for example
- (BOOL)checkIfHasKeys {
    rnp_input_t keyfile = NULL;
    BOOL result = YES;
    
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
    if (result && rnp_ffi_set_pass_provider(_ffi, generate_pass_provider , NULL) != RNP_SUCCESS) {
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

- (nullable NSString*)decryptUsingKeys:(BOOL)usekeys password:(NSString *)password {
    
    BOOL result = YES;
    
    rnp_input_t  keyfile = NULL;
    rnp_input_t  input = NULL;
    rnp_output_t output = NULL;
    uint8_t *    buf = NULL;
    size_t       buf_len = 0;
    
    /* check whether we want to use key or password for decryption */
    if (usekeys) {
        /* load secret keyring, as it is required for public-key decryption. However, you may
         * need to load public keyring as well to validate key's signatures. */
        if (rnp_input_from_path(&keyfile, "secring.pgp") != RNP_SUCCESS) {
            fprintf(stdout, "failed to open secring.pgp. Did you run ./generate sample?\n");
            result = NO;
        }
        
        /* we may use RNP_LOAD_SAVE_SECRET_KEYS | RNP_LOAD_SAVE_PUBLIC_KEYS as well*/
        if (rnp_load_keys(_ffi, self.secFormat, keyfile, RNP_LOAD_SAVE_SECRET_KEYS) != RNP_SUCCESS) {
            fprintf(stdout, "failed to read secring.pgp\n");
            result = NO;
        }
        
        if (result) {
            rnp_input_destroy(keyfile);
        }
        keyfile = NULL;
        
        // TODO: Perform decryption test without password
    }
    
    [PrivateValueManager.shared setObject:password for:PrivateValueKeyPassword];
    if (result && rnp_ffi_set_pass_provider(_ffi, decrypt_pass_provider, NULL) != RNP_SUCCESS) {
        fprintf(stdout, "failed to set pass provider\n");
        result = NO;
    }
    
    // TODO: Think about load input not from file directly
    if (result && rnp_input_from_path(&input, "encrypted.asc") != RNP_SUCCESS) {
        fprintf(stdout, "failed to create input object\n");
        result = NO;
    }
    
    if (result && rnp_output_to_memory(&output, 0) != RNP_SUCCESS) {
        fprintf(stdout, "failed to create output object\n");
        result = NO;
    }
    
    if (result && rnp_decrypt(_ffi, input, output) != RNP_SUCCESS) {
        fprintf(stdout, "public-key decryption failed\n");
        result = NO;
    }
    [PrivateValueManager.shared clearObjectFor:PrivateValueKeyPassword];
    
    /* get the decrypted message from the output structure */
    if (result && rnp_output_memory_get_buf(output, &buf, &buf_len, false) != RNP_SUCCESS) {
        fprintf(stdout, "can't get message from output\n");
        result = NO;
    }
    
    if (result) {
        fprintf(stdout,
                "Decrypted message (%s):\n%.*s\n",
                usekeys ? "with key" : "with password",
                (int) buf_len,
                buf);
    }
    
    rnp_input_destroy(keyfile);
    rnp_input_destroy(input);
    rnp_output_destroy(output);
    
    return result ? [NSString stringWithFormat:@"%s", buf] : NULL;
}

@end
