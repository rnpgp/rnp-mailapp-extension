//
//  UserDefaults.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 01.04.2022.
//

import Foundation

/**
 * UserDefault is an extension for standart user defaults which allow to load and store values. Also, it allow to exchange values between container app and the extensions.
 */
@propertyWrapper
struct UserDefault <Value> {
    let key: UserDefaults.Keys
    let defaultValue: Value
    var container: UserDefaults = UserDefaults.suiteStandard
    
    var wrappedValue: Value {
        get {
            return container.object(forKey: key.rawValue) as? Value ?? defaultValue
        }
        set {
            container.set(newValue, forKey: key.rawValue)
            container.synchronize()
        }
    }
}

extension UserDefaults {
    enum Keys: String {
        case keysList = "keysFilenamesList"
        
    }
}

/// For non-static vars
extension UserDefaults {
    static var suiteStandard: UserDefaults {
        // _NSUserDefaults_Log_Nonsensical_Suites
        /*UserDefaults(suiteName: "com.ribose.Container") ??*/ .standard
    }
}

extension UserDefaults {
    /**
     * Used for store list of the key filesnames as Array of Strings. Will return empty array by default.
     */
    @UserDefault(key: Keys.keysList, defaultValue: [])
    static var keysList: [String]
}
