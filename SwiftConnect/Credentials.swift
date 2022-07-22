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
    @Published public var portal: String?
    @Published public var username: String?
    @Published public var password: String?
    @Published public var sudo_password: String?
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
        //context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration
        if let data = KeychainService.shared.load(context: context, server: "swiftconnect") {
            username = data.username
            password = data.password
            portal = data.portal
        } else {
            portal = ""
            username = "dummy"
            password = ""
        }
        if let data1 = KeychainService.shared.load(context: context, server: "swiftconnect_sudo") {
            sudo_password = data1.password
        } else {
            sudo_password = ""
        }
    }
    
    func save() {
        let _ = KeychainService.shared.insertOrUpdate(credentials: CredentialsData(server: "swiftconnect", portal: portal, username: username, password: password))
        let _ = KeychainService.shared.insertOrUpdate(credentials: CredentialsData(server: "swiftconnect_sudo", portal: "dummy", username: "dummy", password: sudo_password))
    }
}

struct CredentialsData {
    let server: String?
    let portal: String?
    let username: String?
    let password: String?
}

class KeychainService: NSObject {
    public static let shared = KeychainService();
    
    func insertOrUpdate(credentials: CredentialsData) -> Bool {
        let server = credentials.server
        let username = credentials.username
        let password = credentials.password?.data(using: String.Encoding.utf8)
        let portal = credentials.portal
        let status = _insertOrUpdate(server: server, account: username, data: password, description: portal)
        return status
    }
    
    private func _insertOrUpdate(server: String?, account: String?, data: Data?, description: String?) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server as Any,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccount as String: account as Any,
            kSecValueData as String: data as Any,
            kSecAttrDescription as String: description as Any,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrAccount as String: account as Any,
                kSecAttrServer as String: server as Any,
                kSecValueData as String: data as Any,
                kSecAttrDescription as String: description as Any,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        } else {
            return status == errSecSuccess
        }
    }
    
    func load(context: LAContext, server: String) -> CredentialsData? {
        var retVal : CredentialsData?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "read your stored vpn authentication details and device sudo password from the keychain", reply: { (success, error) in
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
            let portal = existingItem[kSecAttrDescription as String] as? String
        else {
            return nil
        }
        
        return CredentialsData(server: server, portal: portal, username: username, password: password)
    }
}
