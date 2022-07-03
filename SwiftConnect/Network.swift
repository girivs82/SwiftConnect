//
//  Network.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 29/06/22.
//

import Foundation
import Network
import SwiftUI

class NetworkPathMonitor: ObservableObject {
    @Published var path: NWPath? = nil
    @Published var tun_intf : Bool? = nil
    static let shared = NetworkPathMonitor()
    
    let monitor = NWPathMonitor()
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.path = path
            for intf in path.availableInterfaces {
                let isOpenconnectRunning = isProcessRunning(executableName: "openconnect")
                print(intf.name, intf.type, isOpenconnectRunning)
                if intf.name.hasPrefix("utun") && isOpenconnectRunning {
                    self?.tun_intf = true
                    break
                    
                }
                else {
                    self?.tun_intf = false
                }
            }
            DispatchQueue.main.async {
                VPNController.shared.state = self!.tun_intf! ? .launched : .stopped
                AppDelegate.shared.networkDidDrop(dropped: !(path.status == .satisfied))
                AppDelegate.shared.vpnConnectionDidChange(connected: self!.tun_intf!)
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
