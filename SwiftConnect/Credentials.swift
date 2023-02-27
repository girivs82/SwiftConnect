//
//  Credentials.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 22/07/22.
//

import Foundation
import LocalAuthentication
import os.log

class Credentials: ObservableObject {
    @Published public var portal: String
    @Published public var username: String?
    @Published public var password: String?
    @Published public var sudo_password: String?
    @Published public var bin_path: String?
    public var preauth: AuthRequestResp? = nil
    public var finalauth: AuthCompleteResp? = nil
    public var samlv2: Bool = false
    @Published var samlv2Token: HTTPCookie?
    public var preAuthCallback: ((AuthRequestResp?) -> ())? = nil
    public var authCookieCallback: ((HTTPCookie?) -> ())? = nil
    public var postAuthCallback: ((AuthCompleteResp?) -> ())? = nil
    let context = LAContext()
    static let shared = Credentials()
    
    init() {
        // Load the default gateway and openconnect binpath Info.plist
        var resourceFileDictionary: NSDictionary?
        var default_gateway: String! = ""
        var openconnect_path: String! = ""
            
            //Load content of Info.plist into resourceFileDictionary dictionary
            if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
                resourceFileDictionary = NSDictionary(contentsOfFile: path)
            }
            
            if let resourceFileDictionaryContent = resourceFileDictionary {
                // Get something from our Info.plist like MinimumOSVersion
                default_gateway = resourceFileDictionaryContent.object(forKey: "DefaultGateway") as? String
                openconnect_path = resourceFileDictionaryContent.object(forKey: "OpenconnectPath") as? String
            }
        
        if let data = KeychainService.shared.load(context: context, server: "swiftconnect", reason: "read your stored vpn authentication details from the keychain") {
            username = data.username
            password = data.password
            portal = data.portal!
            bin_path = data.comment
        } else {
            portal = default_gateway!
            username = "<none>"
            password = ""
            bin_path = openconnect_path!
        }
        // If keychain is defined, but bin_path is empty, fill it from plist
        if bin_path == "" {
            bin_path = openconnect_path!
        }
        // Also load the sudo password from the swiftconnect_sudo keychain entry
        load_sudo_password()
    }
    
    func load_sudo_password() {
        if let data = KeychainService.shared.load(context: context, server: "swiftconnect_sudo", reason: "read your sudo password from the keychain") {
            sudo_password = data.password
        } else {
            sudo_password = ""
        }
    }
    
    func save() {
        let _ = KeychainService.shared.insertOrUpdate(credentials: CredentialsData(server: "swiftconnect", portal: portal, username: username, password: password, comment: bin_path))
        let _ = KeychainService.shared.insertOrUpdate(credentials: CredentialsData(server: "swiftconnect_sudo", portal: "<none>", username: "<none>", password: sudo_password, comment: "<none>"))
    }
}

struct CredentialsData {
    let server: String?
    let portal: String?
    let username: String?
    let password: String?
    let comment: String?
}

enum KeychainError: Error {
    case noPassword
    case unexpectedPasswordData
    case unhandledError(status: OSStatus)
}

class KeychainService: NSObject {
    public static let shared = KeychainService();
    
    func insertOrUpdate(credentials: CredentialsData) -> Bool {
        let server = credentials.server
        let username = credentials.username
        let password = credentials.password?.data(using: String.Encoding.utf8)
        let portal = credentials.portal
        let comment = credentials.comment
        let status = try! _insertOrUpdate(server: server, account: username, data: password, description: portal, comment: comment)
        return status
    }
    
    private func _insertOrUpdate(server: String?, account: String?, data: Data?, description: String?, comment: String?) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server as Any,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccount as String: account as Any,
            kSecValueData as String: data as Any,
            kSecAttrDescription as String: description as Any,
            kSecAttrComment as String: comment as Any,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrAccount as String: account as Any,
                kSecAttrServer as String: server as Any,
                kSecValueData as String: data as Any,
                kSecAttrDescription as String: description as Any,
                kSecAttrComment as String: comment as Any,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
            return status == errSecSuccess
        } else {
            guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
            return status == errSecSuccess
        }
    }
    
    func load(context: LAContext, server: String, reason: String) -> CredentialsData? {
        var retVal : CredentialsData?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { (success, error) in
                if (error != nil) {
                    Logger.vpnProcess.error("\(error!.localizedDescription)")
                    group.leave()
                    return
                }
                if success == true {
                    retVal = self._load(server: server)
                }
                group.leave()
            })
        }
        group.wait()
        return retVal
    }
    
    private func _load(server: String) -> CredentialsData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { return nil }
        
        guard let existingItem = item as? [String : Any],
            let passwordData = existingItem[kSecValueData as String] as? Data,
            let password = String(data: passwordData, encoding: String.Encoding.utf8),
            let username = existingItem[kSecAttrAccount as String] as? String,
            let portal = existingItem[kSecAttrDescription as String] as? String,
            let comment = existingItem[kSecAttrComment as String] as? String
        else {
            return nil
        }
        
        return CredentialsData(server: server, portal: portal, username: username, password: password, comment: comment)
    }
}
