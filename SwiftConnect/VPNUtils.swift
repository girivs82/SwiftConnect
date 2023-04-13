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
import OSLog

enum VPNState {
    case stopped, webauth, processing, launched, viewlogs
    
    var description : String {
      switch self {
      case .stopped: return "stopped"
      case .webauth: return "webauth"
      case .processing: return "launching"
      case .launched: return "launched"
      case .viewlogs: return "viewlogs"
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

struct Server: Identifiable {
    var serverName:String
    let id:String
}

class VPNController: ObservableObject {
    @Published public var state: VPNState = .stopped
    @Published public var proto: VPNProtocol = .anyConnect
    var credentials: Credentials?

    private var currentLogURL: URL?;
    static var stdinPath = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(NSUUID().uuidString)");
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
            if credentials.portal.hasSuffix("SAML-EXT") {
                self.startvpn(ext_browser: true) { succ in
                }
            }
            else if credentials.portal.hasSuffix("SAML") {
                self.authMgr = AuthManager(credentials: credentials, preAuthCallback: preAuthCallback, authCookieCallback: authCookieCallback, postAuthCallback: postAuthCallback)
                self.authMgr!.pre_auth()
            }
        }
        else {
            self.startvpn() { succ in
            }
        }
    }

    public func startvpn(session_token: String? = "", server_cert_hash: String? = "", ext_browser: Bool? = false, _ onLaunch: @escaping (_ succ: Bool) -> Void) {
        state = .processing
        DispatchQueue.global().async {
            Commands.run(samlv2: self.credentials!.samlv2, ext_browser: ext_browser!, proto: self.proto.rawValue, gateway: self.credentials!.portal, path: self.credentials!.bin_path!, username: self.credentials!.username!, password: self.credentials!.password!, session_token: session_token!, server_cert_hash: server_cert_hash!)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            Commands.schedule_conn_check()
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
        // Keep the popup window open until web auth is complete or cancelled
        AppDelegate.shared.pinPopover = true
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
        self.startvpn(session_token: session_token, server_cert_hash: server_cert_hash, ext_browser: false) { succ in
        }
    }
    
    func terminate() {
        state = .processing
        //ProcessManager.shared.terminateProcess(credentials: self.credentials)
        DispatchQueue.global().async {
            Commands.terminate()
            Commands.disable_conn_check()
        }
    }
}

