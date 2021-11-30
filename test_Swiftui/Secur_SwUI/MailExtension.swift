//
//  MailExtension.swift
//  Secur_SwUI
//
//  Created by Sergey Vinogradov on 30.11.2021.
//

import MailKit

class MailExtension: NSObject, MEExtension {
    
    
    
    func handlerForMessageSecurity() -> MEMessageSecurityHandler {
        // Use a shared instance for all messages, since there's
        // no state associated with the security handler.
        return MessageSecurityHandler.shared
    }

}

