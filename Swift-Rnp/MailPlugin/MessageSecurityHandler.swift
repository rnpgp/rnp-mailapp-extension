//
//  MessageSecurityHandler.swift
//  MailPlugin
//
//  Created by Sergey Vinogradov on 26.11.2021.
//

import MailKit

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    static let shared = MessageSecurityHandler()
    
    override init() {
        rnp = RnpFacade(pubFormat: .gpg, secFormat: .gpg)
        
        messageDecoder = RnpMessageDecoder(rnp: rnp)
        messageEncoder = RnpMessageEncoder(rnp: rnp)
    }
    
    private var rnp: RnpFacade
    private var messageDecoder: RnpMessageDecoder
    private var messageEncoder: RnpMessageEncoder

    // MARK: - Encoding Messages

    func getEncodingStatus(for message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        completionHandler(messageEncoder.encodingStatus(for: message, composeContext: composeContext))
    }

    func encode(_ message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        completionHandler(messageEncoder.encode(message, composeContext: composeContext))
    }

    // MARK: - Decoding Messages

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        return messageDecoder.decodedMessage(from: data)
    }
 
    // MARK: - Displaying Security Information

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        return MessageSecurityViewController(nibName: "MessageSecurityViewController", bundle: Bundle.main)
    }

    // MARK: mark - Displaying Additional Context

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        // Return a view controller that can show additional message context.
        return nil
    }

    func primaryActionClicked(forMessageContext context: Data, completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        // Provide a view controller that is displayed when user clicks on the message banner that is displayed when viewing a decoded mail message.
        completionHandler(nil)
    }
}
