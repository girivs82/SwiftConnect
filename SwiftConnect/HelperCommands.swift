//
//  HelperCommands.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 09/04/23.
//

import Foundation
import ServiceManagement
import XPCOverlay

let agentPlist = "com.xpc.swiftconnect.agent.plist"
let agentService = "com.xpc.swiftconnect.agent.hello"

class Commands {
    
    static var state: String = "UNTRUSTED"
    class func register() {
        let service = SMAppService.agent(plistName: agentPlist)

        do {
            try service.register()
            print("Successfully registered \(service)")
        } catch {
            print("Unable to register \(error)")
            exit(1)
        }
    }

    class func unregister() {
        let service = SMAppService.agent(plistName: agentPlist)

        do {
            try service.unregister()
            print("Successfully unregistered \(service)")
        } catch {
            print("Unable to unregister \(error)")
            exit(1)
        }
    }

    class func status() {
        let service = SMAppService.agent(plistName: agentPlist)

        print("\(service) has status \(service.status)")
    }
    
    class func test(withMessage message: String) {
        let request = xpc_dictionary_create_empty()
        message.withCString { rawMessage in
            xpc_dictionary_set_string(request, "MessageKey", rawMessage)
        }

        var error: xpc_rich_error_t? = nil
        let session = xpc_session_create_mach_service(agentService, nil, .none, &error)
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
    
    class func run(samlv2: Bool, ext_browser: Bool, path: String, session_token: String, server_cert_hash: String, protocol: String, gateway: String) {
        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(request, "command", "Connect")
        xpc_dictionary_set_bool(request, "useSAMLv2", samlv2)
        xpc_dictionary_set_bool(request, "extBrowser", ext_browser)
        xpc_dictionary_set_string(request, "vpnGateway", gateway)
        xpc_dictionary_set_string(request, "openconnectPath", path)

        var error: xpc_rich_error_t? = nil
        let session = xpc_session_create_mach_service(agentService, nil, .none, &error)
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
}

