//
//  PrivateValueManager.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 24.12.2021.
//

import Foundation

@objc
public enum PrivateValueKey: Int {
    case password
}

extension PrivateValueKey: RawRepresentable {
    public typealias RawValue = String
    
    public var rawValue: RawValue {
        switch self {
        case .password:
            return "PASSWORD"
        }
    }
    
    public init?(rawValue: RawValue) {
        switch rawValue {
        case "PASSWORD":
            self = .password
        default:
            return nil
        }
    }
}

final public class PrivateValueManager: NSObject {
    
    @objc public
    static let shared = PrivateValueManager()
    
    private var values: [PrivateValueKey: AnyObject] = [:]
    
    private override init() {
        
    }
    
    @objc public
    func setObject(_ anyObject: AnyObject, for key: PrivateValueKey) {
        values[key] = anyObject
    }
    
    @objc public
    func objectFor(_ key: PrivateValueKey) -> AnyObject? {
        guard let obj = values[key] else { return nil }
        return obj
    }
    
    @objc public
    func clearObjectFor(_ key: PrivateValueKey) {
        values[key] = nil
    }
}
