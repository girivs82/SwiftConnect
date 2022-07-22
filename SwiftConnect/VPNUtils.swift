//
//  VPNUtils.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import Foundation
import SwiftUI
import Security
import os.log

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
    var credentials: Credentials?

    private var currentLogURL: URL?;
    static var stdinPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
    static var sudo_pass: String?;
    private var authMgr: AuthManager?;
    private var authReqResp: AuthRequestResp?;
    static let shared = VPNController()
    
    func initialize (credentials: Credentials?) {
        self.credentials = credentials
    }

    func start(credentials: Credentials, save: Bool) {
        self.credentials = credentials
        if save {
            credentials.save()
        }
        if credentials.samlv2 {
            self.authMgr = AuthManager(credentials: credentials, preAuthCallback: preAuthCallback, authCookieCallback: authCookieCallback, postAuthCallback: postAuthCallback)
            self.authMgr!.pre_auth()
        }
        else {
            self.startvpn() { succ in
            }
        }
    }
    
    public func startvpn(session_token: String? = "", server_cert_hash: String? = "", _ onLaunch: @escaping (_ succ: Bool) -> Void) {
        state = .processing
        
        // Prepare commands
        Logger.vpnProcess.info("[openconnect] start")
        if credentials!.samlv2 {
            ProcessManager.shared.launch(tool: URL(fileURLWithPath: "/usr/bin/sudo"),
                                         arguments: ["-k", "-S", "openconnect", "-b", "--protocol=\(proto)", "--pid-file=/var/run/openconnect.pid", "--cookie-on-stdin", "--servercert=\(server_cert_hash!)", "\(credentials!.portal!)/SAML"],
                input: Data("\(credentials!.sudo_password!)\n\(session_token!)\n".utf8)) { status, output in
                    Logger.vpnProcess.info("[openconnect] completed")
                }
        }
        else {
            ProcessManager.shared.launch(tool: URL(fileURLWithPath: "/usr/bin/sudo"),
                                         arguments: ["-k", "-S", "openconnect", "-b", "--protocol=\(proto)", "--pid-file=/var/run/openconnect.pid", "-u", "\(credentials!.username!)", "--passwd-on-stdin", "\(credentials!.portal!)"],
                                         input: Data("\(credentials!.sudo_password!)\n\(credentials!.password!)\n".utf8)) { status, output in
                    Logger.vpnProcess.info("[openconnect] completed")
                }
        }
        Logger.vpnProcess.info("[openconnect] launched")
        AppDelegate.shared.pinPopover = false
    }
    
    func preAuthCallback(authResp: AuthRequestResp?) -> Void {
        self.authReqResp = authResp
        if let err = authResp!.auth_error {
            Logger.vpnProcess.error("\(err)")
            return
        }
        state = .webauth
    }
    
    func authCookieCallback(cookie: HTTPCookie?) -> Void {
        guard let uCookie = cookie else {
            Logger.vpnProcess.error("authCookieCallback: Cookie not received!!!")
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
            Logger.vpnProcess.error("postAuthCallback: Session cookie not found!!!")
            return
        }
        let server_cert_hash = authResp?.server_cert_hash
        self.startvpn(session_token: session_token, server_cert_hash: server_cert_hash) { succ in
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
        ProcessManager.shared.terminateProcess(credentials: self.credentials)
    }
    
    func openLogFile() {
        if let url = currentLogURL {
            NSWorkspace.shared.open(url)
        }
    }
}

