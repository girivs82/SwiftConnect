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
    
    let monitor = NWPathMonitor()
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.path = path
                for intf in path.availableInterfaces {
                    print(intf.name, intf.type)
                    if intf.name.hasPrefix("utun") {
                        self?.tun_intf = true
                    }
                    else {
                        self?.tun_intf = false
                    }
                }
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
