//
//  Network.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 29/06/22.
//

import Foundation
import Network
import SwiftUI
import os.log

class NetworkPathMonitor: ObservableObject {
    @Published var path: NWPath? = nil
    static let shared = NetworkPathMonitor()
    var vpn_intf: String?
    
    let monitor = NWPathMonitor()
    
    init() {
        monitor.pathUpdateHandler = { path in
            var vpn_intf_enabled = false
            for intf in path.availableInterfaces {
                let intf_info = "\(intf.name), \(intf.type)"
                Logger.vpnProcess.info("\(intf_info)")
                if intf.name == self.vpn_intf {
                    vpn_intf_enabled = true
                    break
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let vpn_intf = vpn_intf_enabled && Commands.is_running()
                AppDelegate.shared.vpnConnectionDidChange(connected: vpn_intf)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }
    
    func cancel() {
        monitor.cancel()
    }
    
    deinit {
        cancel()
    }
}
