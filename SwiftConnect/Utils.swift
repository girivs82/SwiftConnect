//
//  Utils.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 30/06/22.
//

import SwiftUI
import Foundation
import Darwin
import os.log

func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

/// Called when the tool has terminated.
///
/// This must be run on the main queue.
///
/// - Parameters:
///   - result: Either the tool’s termination status or, if something went
///   wrong, an error indicating what that was.
///   - output: Data captured from the tool’s `stdout`.

typealias CompletionHandler = (_ result: Result<Int32, Error>, _ output: Data) -> Void

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    /// Logs the view cycles like viewDidLoad.
    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
    static let vpnProcess = Logger(subsystem: subsystem, category: "vpnProcess")
}

func load_gateways_from_plist(plist_name: String) -> [Server] {
    // Load the gateways from the provided plist name
    var resourceFileDictionary: NSDictionary?
    var serverlist = [Server]()
        
    //Load content of Info.plist into resourceFileDictionary dictionary
    if let path = Bundle.main.path(forResource: plist_name, ofType: "plist") {
        resourceFileDictionary = NSDictionary(contentsOfFile: path)
    }
    
    if let resourceFileDictionaryContent = resourceFileDictionary {
        
        // Get something from our Info.plist like MinimumOSVersion
        let serverarray = ((resourceFileDictionaryContent.object(forKey: "AnyConnectProfile") as! NSDictionary).object(forKey: "ServerList") as! NSDictionary).object(forKey: "HostEntry")! as! NSArray
        //print(serverlist)
        for item in serverarray {
            let obj = item as! NSDictionary
            let key = obj.object(forKey: "HostName") as! String
            let val = "https://" + (obj.object(forKey: "HostAddress") as! String)
            let server = Server(serverName: key, id: val)
            serverlist.append(server)
            //Or we can print out entire Info.plist dictionary to preview its content
            //print(resourceFileDictionaryContent)
        }
    }
    return serverlist
}

private var urlSession:URLSession = {
    var newConfiguration:URLSessionConfiguration = .default
    newConfiguration.waitsForConnectivity = false
    newConfiguration.allowsCellularAccess = true
    return URLSession(configuration: newConfiguration)
}()

public func canReachServer(server: String) -> Bool
{
    let url = URL(string: server)
    let semaphore = DispatchSemaphore(value: 0)
    var success = false
    let task = urlSession.dataTask(with: url!)
    { data, response, error in
        if error != nil
        {
            success = false
        }
        else
        {
            success = true
        }
        semaphore.signal()
    }

    task.resume()
    semaphore.wait()

    return success
}
