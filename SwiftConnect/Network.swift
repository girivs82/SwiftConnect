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
    private var tun_intf : Bool? = nil
    
    let monitor = NWPathMonitor()
    
    init() {
        monitor.pathUpdateHandler = { path in
            var tun_intf = false
            for intf in path.availableInterfaces {
                let intf_info = "\(intf.name), \(intf.type)"
                Logger.vpnProcess.info("\(intf_info)")
                tun_intf = intf.name.hasPrefix("utun")
                if tun_intf == true {
                    break
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let vpn_intf = (tun_intf == true) && Commands.is_running()
                VPNController.shared.state = vpn_intf ? .launched : .stopped
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
