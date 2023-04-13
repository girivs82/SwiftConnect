//
//  HelperCommands.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 09/04/23.
//

import Foundation
import ServiceManagement
import XPCOverlay

let daemonPlist = "com.xpc.swiftconnect.daemon.plist"
let daemonService = "com.xpc.swiftconnect.daemon.privileged_exec"

class Commands {
    
    static var state: String = "UNTRUSTED"
    static var listener: xpc_connection_t = xpc_null_create()
    
    class func register() {
        DispatchQueue.global().async {
            let service = SMAppService.daemon(plistName: daemonPlist)
            
            do {
                try service.register()
                print("Successfully registered \(service)")
            } catch {
                print("Unable to register \(error)")
                exit(1)
            }
        }
    }
    
    class func unregister() {
        DispatchQueue.global().async {
            let service = SMAppService.daemon(plistName: daemonPlist)
            
            do {
                try service.unregister()
                print("Successfully unregistered \(service)")
            } catch {
                print("Unable to unregister \(error)")
                exit(1)
            }
        }
    }
    
    class func status() -> SMAppService.Status {
        let service = SMAppService.daemon(plistName: daemonPlist)
        
        print("\(service) has status \(service.status)")
        return service.status
    }
    
    class func run(samlv2: Bool, ext_browser: Bool, proto: String, gateway: String, path: String,  username: String, password: String, session_token: String, server_cert_hash: String) {
        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(request, "command", "connect")
        xpc_dictionary_set_bool(request, "useSAMLv2", samlv2)
        xpc_dictionary_set_bool(request, "extBrowser", ext_browser)
        xpc_dictionary_set_string(request, "protocol", proto)
        xpc_dictionary_set_string(request, "vpnGateway", gateway)
        xpc_dictionary_set_string(request, "openconnectPath", path)
        xpc_dictionary_set_string(request, "username", username)
        xpc_dictionary_set_string(request, "password", password)
        xpc_dictionary_set_string(request, "sessionToken", session_token)
        xpc_dictionary_set_string(request, "serverCertHash", server_cert_hash)
        
        var error: xpc_rich_error_t? = nil
        let queue = DispatchQueue(label: "com.mikaana.SwiftConnect.privileged_exec")
        let session = xpc_session_create_mach_service(daemonService, queue, .none, &error)
        if let error = error {
            print("Unable to create xpc_session \(error)")
            exit(1)
        }
        
        let reply = xpc_session_send_message_with_reply_sync(session!, request, &error)
        if let error = error {
            print("Error sending message \(error)")
            exit(1)
        }
        
        let response = xpc_dictionary_get_string(reply!, "ResponseKey")
        let encodedResponse = String(cString: response!)
        
        print("Received \"\(encodedResponse)\"")
        
        xpc_session_cancel(session!)
    }
    
    class func terminate() {
        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(request, "command", "disconnect")
        
        var error: xpc_rich_error_t? = nil
        let queue = DispatchQueue(label: "com.mikaana.SwiftConnect.privileged_exec")
        let session = xpc_session_create_mach_service(daemonService, queue, .none, &error)
        if let error = error {
            print("Unable to create xpc_session \(error)")
            exit(1)
        }
        
        let reply = xpc_session_send_message_with_reply_sync(session!, request, &error)
        if let error = error {
            print("Error sending message \(error)")
            exit(1)
        }
        
        let response = xpc_dictionary_get_string(reply!, "ResponseKey")
        let encodedResponse = String(cString: response!)
        
        print("Received \"\(encodedResponse)\"")
        
        xpc_session_cancel(session!)
    }
    
    class func is_running() -> Bool {
        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(request, "command", "is_running")
        
        var error: xpc_rich_error_t? = nil
        let queue = DispatchQueue(label: "com.mikaana.SwiftConnect.privileged_exec")
        let session = xpc_session_create_mach_service(daemonService, queue, .none, &error)
        if let error = error {
            print("Unable to create xpc_session \(error)")
            exit(1)
        }
        
        let reply = xpc_session_send_message_with_reply_sync(session!, request, &error)
        if let error = error {
            print("Error sending message \(error)")
            exit(1)
        }
        
        let response = xpc_dictionary_get_bool(reply!, "ResponseKey")
        
        print("Received \"\(response)\"")
        
        xpc_session_cancel(session!)
        return response
    }
    
    class func create_listener() {
        let queue = DispatchQueue(label: "com.mikaana.SwiftConnect.proc_status")
        listener = xpc_connection_create_mach_service("com.xpc.swiftconnect.daemon.privileged_exec", queue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        print(listener)
        
        xpc_connection_set_event_handler(listener) { peer in
            var cmd: String = ""
            if xpc_get_type(peer) != XPC_TYPE_CONNECTION {
                return
            }
            xpc_connection_set_event_handler(peer) { request in
                if xpc_get_type(request) == XPC_TYPE_DICTIONARY {
                    cmd = String(cString: xpc_dictionary_get_string(request, "command")!)
                    print(cmd)
                    if cmd == "vpn_disconnected" {
                        print("Disconnected")
                        
                    }
                    else if cmd == "vpn_reconnected" {
                        print("Reconnected")
                    }
                }
            }
            //xpc_connection_activate(peer)
        }
        //xpc_connection_activate(listener)
    }
}


