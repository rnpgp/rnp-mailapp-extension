//
//  RnpFacade.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 02.12.2021.
//

import Foundation

class RnpFacade {
    
    /// By default you can use GPG
    private static let defaultKeysFormat = RnpKeyStoreFormat.gpg.rawValue
    
    /**
     Check if keys files are presented
     - returns:`true` in case of files are on the place
     - warning: It return `false` in any error cace
     */
    @discardableResult
    static func hasKeys() -> Bool {
        wHasKeys(RnpFacade.defaultKeysFormat, RnpFacade.defaultKeysFormat) == 1
    }
    
    /**
     Try to create keys files
     - returns:`true` in case of keys was created and files are saved succesfully
     - warning: Keys will be created on ~/Library/Containers/**BuildID**/Data/, so for container app and the plugin **BuildID** should be the same
     */
    @discardableResult
    static func createKeys() -> Bool {
        wCreateKeys(RnpFacade.defaultKeysFormat, RnpFacade.defaultKeysFormat) == 1
    }
}

/*
// Not working/stuck because incompatibility types of callback/enclosure on interloop - the origin of requirements of the wrapper.
 /// TODO: remove it after closest commit
class Example {
    /// this example function generates RSA/RSA and Eddsa/X25519 keypairs
    static func generateKeys() {
        let ffi = UnsafeMutablePointer<rnp_ffi_t?>.allocate(capacity: 1)
        defer {
            ffi.deallocate()
        }


//        var result = 1
        // initialize FFI object
        guard rnp_ffi_create(ffi, RnpKeyStoreFormat.gpg.rawValue, RnpKeyStoreFormat.gpg.rawValue) == RnpResult.success.rawValue else {
            return
        }
        print(ffi)

//        var ffi2: rnp_ffi_t = ffi
//
//        // set password provider
////        guard let theFfi = ffi as? rnp_ffi_t? else { return }
//        rnp_ffi_set_pass_provider(ffi2, { aFfi, app_ctx_up, rnp_key_handle_t_opt, cchar_up_opt, cchar_up_opt2, anInt in
//            print()
//            return false
//        }, nil)
//        if (rnp_ffi_set_pass_provider(ffi, example_pass_provider, NULL)) {
//            goto finish;
//        }
    }
}
 */
