//
//  VPNUtils.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import Foundation
import SwiftShell
import SwiftUI
import Security

extension Dictionary where Key:Hashable {
    public func filterToDictionary <C: Collection> (keys: C) -> [Key:Value]
        where C.Iterator.Element == Key {

        var result = [Key:Value](minimumCapacity: keys.count)
        for key in keys { result[key] = self[key] }
        return result
    }
}


enum VPNState {
    case stopped, webauth, processing, launched
    
    var description : String {
      switch self {
      case .stopped: return "stopped"
      case .webauth: return "webauth"
      case .processing: return "launching"
      case .launched: return "launched"
      }
    }
}

enum VPNProtocol: String, Equatable, CaseIterable {
    case globalProtect = "gp", anyConnect = "anyconnect"
    
    var id: String {
        return self.rawValue
    }
    
    var name: String {
        switch self {
        case .globalProtect: return "GlobalProtect"
        case .anyConnect: return "AnyConnect"
        }
    }
}

class VPNController: ObservableObject {
    @Published public var state: VPNState = .stopped
    @Published public var proto: VPNProtocol = .anyConnect
    @EnvironmentObject var credentials: Credentials

    private var currentLogURL: URL?;
    static var stdinPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
    static var sudo_pass: String?;
    private var url: String?;
    private var sudo_password: String?
    private var authMgr: AuthManager?;
    private var authReqResp: AuthRequestResp?;
    private var runCommand : AsyncCommand?;
    var context = CustomContext(main)
    
    static let shared = VPNController()
    
    func start(credentials: Credentials, save: Bool) {
        
        if save {
            credentials.save()
        }
        self.url = credentials.portal
        self.sudo_password = credentials.sudo_password
        VPNController.sudo_pass = self.sudo_password
        self.authMgr = AuthManager(credentials: credentials, preAuthCallback: preAuthCallback, authCookieCallback: authCookieCallback, postAuthCallback: postAuthCallback)
        self.authMgr!.pre_auth()
    }
    
    public func startvpn(portal: String?, session_token: String?, server_cert_hash: String?, _ onLaunch: @escaping (_ succ: Bool) -> Void) {
        state = .processing
        
        // Prepare commands
        print("[openconnect] start")
        //Self.killOpenConnect()
        // stdin to input cookie
        let stdinStr = self.sudo_password! + "\n"
        try! stdinStr.write(to: Self.stdinPath, atomically: true, encoding: .utf8)
        let stdin = try! FileHandle(forReadingFrom: Self.stdinPath)
        // stdout for logging
        let stdoutPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
        try! "".write(to: stdoutPath, atomically: true, encoding: .utf8)
        let stdout = try! FileHandle(forReadingFrom: stdoutPath)

        currentLogURL = stdoutPath
        print("[openconnect] stdout log: \(stdoutPath.path)")
        print("[openconnect] stdin pending: \(VPNController.stdinPath.path)") //REMOVE THIS: sensitive information in stdin should not be logged
        // Run
        
        // Prepare an environment as close to a new OS X user account as possible with the exception of PATH variable, where /opt/homebrew/bin is also added to discover openconnect
        let cleanenvvars = ["TERM_PROGRAM", "SHELL", "TERM", "TMPDIR", "Apple_PubSub_Socket_Render", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "USER", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING", "XPC_FLAGS", "XPC_SERVICE_NAME", "SHLVL", "HOME", "LOGNAME", "LC_CTYPE", "_"]
        context.env = context.env.filterToDictionary(keys: cleanenvvars)
        context.env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        context.stdin = FileHandleStream(stdin, encoding: .utf8)
        let shellCommand = "sudo -S openconnect -C \(session_token!) --servercert=\(server_cert_hash!) \(portal!)/SAML"
        self.runCommand = context.runAsync(bash: "\(shellCommand) &> \(stdoutPath.path)").onCompletion { _ in
            try! "".write(to: Self.stdinPath, atomically: true, encoding: .utf8)
            try? stdin.close()
            try? stdout.close()
            print("[openconnect] completed")
        }
        try! "".write(to: Self.stdinPath, atomically: true, encoding: .utf8)
        print("[openconnect] launched")
        print("[openconnect] cmd: \(shellCommand)")
        AppDelegate.shared.pinPopover = false
    }
    
    func preAuthCallback(authResp: AuthRequestResp?) -> Void {
        self.authReqResp = authResp
        if authResp!.auth_error == nil {
            state = .webauth
        }
        else {
            print("preAuthCallback: Error in HTTP RESPONSE!!!", authResp as Any)
        }
    }
    
    func authCookieCallback(cookie: HTTPCookie?) -> Void {
        guard let uCookie = cookie else {
            print("authCookieCallback: Cookie not received!!!", cookie as Any)
            return
        }
        state = .processing
        AppDelegate.shared.pinPopover = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AppDelegate.shared.closePopover()
        }
        self.authMgr!.finish_auth(authReqResp: self.authReqResp, cookie: uCookie)
    }
    
    func postAuthCallback(authResp: AuthCompleteResp?) -> Void  {
        guard let session_token = authResp?.session_token else {
            print("postAuthCallback: Session cookie not found!!! HTTP RESPONSE: ", authResp as Any)
            return
        }
        let server_cert_hash = authResp?.server_cert_hash
        self.startvpn(portal: self.url!, session_token: session_token, server_cert_hash: server_cert_hash) { succ in
        }
    }
    
    func watchLaunch(file: FileHandle, callback: @escaping () -> Void) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: file.fileDescriptor,
            eventMask: .extend,
            queue: DispatchQueue.main
        )
        source.setEventHandler {
            guard source.data.contains(.extend) else { return }
        }
        source.setCancelHandler {
            try? file.close()
        }
        file.seekToEndOfFile()
        source.resume()
    }
    
    func terminate() {
        state = .processing
        let sudo_password = Credentials().sudo_password! + "\n"
        try! sudo_password.write(to: Self.stdinPath, atomically: true, encoding: .utf8)
        var context = CustomContext(main)
        let stdin = try! FileHandle(forReadingFrom: Self.stdinPath)
        context.stdin = FileHandleStream(stdin, encoding: .utf8)
        context.runAsync("sudo", "-S", "pkill", "openconnect").onCompletion { _ in
            try! "".write(to: Self.stdinPath, atomically: true, encoding: .utf8)
            try? stdin.close()

            if FileManager.default.fileExists(atPath: VPNController.stdinPath.path) {
                // delete file
                do {
                    try FileManager.default.removeItem(atPath: VPNController.stdinPath.path)
                } catch {
                    print("Could not delete file, probably read-only filesystem")
                }
            }
        }
    }
    
    func openLogFile() {
        if let url = currentLogURL {
            NSWorkspace.shared.open(url)
        }
    }
}



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
    
    init() {
        if let data = KeychainService.shared.load(server: "swiftconnect") {
            username = data.username
            password = data.password
            portal = data.portal
        } else {
            portal = ""
            username = "dummy"
            password = ""
        }
        if let data1 = KeychainService.shared.load(server: "swiftconnect_sudo") {
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
    
    func load(server: String) -> CredentialsData? {
        return _load(server: server)
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
