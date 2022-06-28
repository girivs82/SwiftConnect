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
    @Published public var openconnectPath: String = "/opt/homebrew/bin/openconnect"
    @EnvironmentObject var credentials: Credentials
    
    private var currentLogURL: URL?;
    private var url: String?;
    private var authMgr: AuthManager?;
    private var authReqResp: AuthRequestResp?;
    
    func start(credentials: Credentials, save: Bool) {
        
        if save {
            credentials.save()
        }
        self.url = credentials.portal
        self.authMgr = AuthManager(credentials: credentials, preAuthCallback: preAuthCallback, authCookieCallback: authCookieCallback, postAuthCallback: postAuthCallback)
        self.authMgr!.pre_auth()
    }
    
    public func startvpn(portal: String?, session_token: String?, server_cert_hash: String?, _ onLaunch: @escaping (_ succ: Bool) -> Void) {
        state = .processing
        AppDelegate.shared.vpnConnectionDidChange(connected: false)
        
        // Prepare commands
        print("[openconnect] start")
        Self.killOpenConnect()
        // stdin to input cookie
        let stdinPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
        try! session_token?.write(to: stdinPath, atomically: true, encoding: .utf8)
        let stdin = try! FileHandle(forReadingFrom: stdinPath)
        // stdout for logging
        let stdoutPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
        try! "".write(to: stdoutPath, atomically: true, encoding: .utf8)
        let stdout = try! FileHandle(forReadingFrom: stdoutPath)
        currentLogURL = stdoutPath
        print("[openconnect] log: \(stdoutPath.path)")
        print("[openconnect] log: \(stdinPath.path)")
        // Run
        var context = CustomContext(main)
        context.stdin = FileHandleStream(stdin, encoding: .utf8)
        let shellCommand = "sudo \(openconnectPath) --cookie-on-stdin --servercert=\(server_cert_hash!) \(portal!)/SAML"
        var launched = false;
        _ = context.runAsync(bash: "\(shellCommand) &> \(stdoutPath.path)").onCompletion { _ in
            if self.state != .stopped {
                DispatchQueue.main.async {
                    if self.state != .stopped {
                        self.state = .stopped
                        AppDelegate.shared.vpnConnectionDidChange(connected: false)
                    }
                }
            }
            if !launched {
                onLaunch(false)
            }
            try? stdout.close()
            print("[openconnect] completed")
        }
        print("[openconnect] cmd: \(shellCommand)")
        
        watchLaunch(file: stdout) {
            print("[openconnect] launched")
            launched = true;
            onLaunch(true)
        }
    }
    
    func preAuthCallback(authResp: AuthRequestResp?) -> Void {
        self.authReqResp = authResp
        if authResp!.auth_error == nil {
            state = .webauth
        }
    }
    
    func authCookieCallback(cookie: HTTPCookie?) -> Void {
        self.state = .processing
        AppDelegate.shared.pinPopover = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AppDelegate.shared.closePopover()
        }
        self.authMgr!.finish_auth(authReqResp: self.authReqResp, cookie: cookie)
    }
    
    func postAuthCallback(authResp: AuthCompleteResp?) -> Void  {
        let session_token = authResp?.session_token
        let server_cert_hash = authResp?.server_cert_hash
        startvpn(portal: self.url!, session_token: session_token, server_cert_hash: server_cert_hash) { succ in
            AppDelegate.shared.pinPopover = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AppDelegate.shared.closePopover()
            }
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
            if self.state == .processing {
                self.state = .launched
                AppDelegate.shared.vpnConnectionDidChange(connected: true)
                callback()
            }
        }
        source.setCancelHandler {
            try? file.close()
        }
        file.seekToEndOfFile()
        source.resume()
    }
    
    func kill() {
        state = .processing
        Self.killOpenConnect();
        state = .stopped
        AppDelegate.shared.vpnConnectionDidChange(connected: false)
    }
    
    static func killOpenConnect(force: Bool = false) {
        let kill_signal = (force) ? "-SIGKILL" : "-SIGTERM"
        run("sudo", "pkill", kill_signal, "openconnect")
    }
    
    func openLogFile() {
        if let url = currentLogURL {
            NSWorkspace.shared.open(url)
        }
    }
}



class Credentials: ObservableObject {
    @Published public var portal: String
    @Published public var username: String
    @Published public var password: String
    public var preauth: AuthRequestResp? = nil
    public var finalauth: AuthCompleteResp? = nil
    public var samlv2: Bool = false
    @Published var samlv2Token: HTTPCookie?
    public var preAuthCallback: ((AuthRequestResp?) -> ())? = nil
    public var authCookieCallback: ((HTTPCookie?) -> ())? = nil
    public var postAuthCallback: ((AuthCompleteResp?) -> ())? = nil
    
    init() {
        if let data = KeychainService.shared.load() {
            username = data.username
            password = data.password
            portal = data.portal
        } else {
            portal = "***REMOVED***"
            username = ""
            password = ""
        }
    }
    
    func save() {
        let _ = KeychainService.shared.insertOrUpdate(credentials: CredentialsData(portal: portal, username: username, password: password))
    }
}

struct CredentialsData {
    let portal: String
    let username: String
    let password: String
}

class KeychainService: NSObject {
    public static let shared = KeychainService();
    
    private static let server = ""
    
    func insertOrUpdate(credentials: CredentialsData) -> Bool {
        let username = credentials.username
        let password = credentials.password.data(using: String.Encoding.utf8)!
        let portal = credentials.portal
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: Self.server,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccount as String: username,
            kSecValueData as String: password,
            kSecAttrDescription as String: portal,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrAccount as String: username,
                kSecAttrServer as String: Self.server,
                kSecValueData as String: password,
                kSecAttrDescription as String: portal,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        } else {
            return status == errSecSuccess
        }
    }
    
    func load() -> CredentialsData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: Self.server,
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
        
        return CredentialsData(portal: portal, username: username, password: password)
    }
}
