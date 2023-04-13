//
//  main.swift
//  SwiftConnect-helper launch daemon
//
//  Created by Shankar Giri Venkita Giri on 09/04/23.
//

import Foundation
import os.log

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let openconnect = Logger(subsystem: subsystem, category: "openconnect")
}

func launch(samlv2: Bool, ext_browser: Bool, openconnect_path: String, proto: String, gateway: String, session_token: String, server_cert_hash: String, username: String, password: String) {
    // Prepare commands
    Logger.openconnect.info("start")
    if samlv2 {
        // External browser invocation
        if ext_browser {
            ProcessManager.shared.launch(tool: URL(fileURLWithPath: openconnect_path), arguments: ["--protocol=\(proto)", "\(gateway)"]) { status, output in
                Logger.openconnect.info("completed")
            }
        }
        // SAMLv2 using embedded webkit based session
        else {
            ProcessManager.shared.launch(tool: URL(fileURLWithPath: openconnect_path), arguments: [ "--protocol=\(proto)", "--cookie-on-stdin", "--servercert=\(server_cert_hash)", "\(gateway)"], input: Data("\(session_token)\n".utf8)) { status, output in
                Logger.openconnect.info("completed")
            }
        }
    }
    // Non SAML based auth
    else {
        ProcessManager.shared.launch(tool: URL(fileURLWithPath: openconnect_path), arguments: ["--protocol=\(proto)", "-u", "\(username)", "--passwd-on-stdin", "\(gateway)"], input: Data("\(password)\n".utf8)) { status, output in
                Logger.openconnect.info("completed")
            }
    }
    Logger.openconnect.info("[openconnect] launched")
}

let queue = DispatchQueue(label: "com.mikaana.SwiftConnect.privileged_exec")
let listener = xpc_connection_create_mach_service("com.xpc.swiftconnect.daemon.privileged_exec", queue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))

xpc_connection_set_event_handler(listener) { peer in
    var cmd: String = ""
    var samlv2: Bool = false
    var ext_browser: Bool = false
    var proto: String = ""
    var gateway: String = ""
    var openconnect_path: String = ""
    var username: String = ""
    var password: String = ""
    var session_token: String = ""
    var server_cert_hash: String = ""
    //Logger.openconnect.info("\(listener.debugDescription!)")
    if xpc_get_type(peer) != XPC_TYPE_CONNECTION {
        return
    }
    xpc_connection_set_event_handler(peer) { request in
        if xpc_get_type(request) == XPC_TYPE_DICTIONARY {
            cmd = String(cString: xpc_dictionary_get_string(request, "command")!)
            if cmd == "connect" {
                samlv2 = xpc_dictionary_get_bool(request, "useSAMLv2")
                ext_browser = xpc_dictionary_get_bool(request, "extBrowser")
                proto = String(cString: xpc_dictionary_get_string(request, "protocol")!)
                gateway = String(cString: xpc_dictionary_get_string(request, "vpnGateway")!)
                openconnect_path = String(cString: xpc_dictionary_get_string(request, "openconnectPath")!)
                username = String(cString: xpc_dictionary_get_string(request, "username")!)
                password = String(cString: xpc_dictionary_get_string(request, "password")!)
                session_token = String(cString: xpc_dictionary_get_string(request, "sessionToken")!)
                server_cert_hash = String(cString: xpc_dictionary_get_string(request, "serverCertHash")!)
                DispatchQueue.main.async {
                    launch(samlv2: samlv2, ext_browser: ext_browser, openconnect_path: openconnect_path, proto: proto, gateway: gateway, session_token: session_token, server_cert_hash: server_cert_hash, username: username, password: password)
                }
            }
            else if cmd == "disconnect" {
                DispatchQueue.main.async {
                    ProcessManager.shared.terminateProcess()
                }
            }
            else if cmd == "is_running" {
                let is_running = ProcessManager.shared.isProcRunning()
                let reply = xpc_dictionary_create_reply(request)
                xpc_dictionary_set_bool(reply!, "ResponseKey", is_running)
                xpc_connection_send_message(peer, reply!)
            }
            else if cmd == "proc_stat" {
                let proc_stat = ProcessManager.shared.openconnect_status
                let reply = xpc_dictionary_create_reply(request)
                xpc_dictionary_set_bool(reply!, "ResponseKey", proc_stat)
                xpc_connection_send_message(peer, reply!)
            }
        }
    }
    xpc_connection_activate(peer)
}

xpc_connection_activate(listener)

dispatchMain()

