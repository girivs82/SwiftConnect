//
//  Utils.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 30/06/22.
//
// Added GetBSDProcessList() from https://github.com/soh335/GetBSDProcessList/blob/master/GetBSDProcessList/GetBSDProcessList.swift and modified to fix compilation errors

import SwiftUI
import Foundation
import Darwin

func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

public func GetBSDProcessList() -> ([kinfo_proc]?)  {

    var done = false
    var result: [kinfo_proc]?
    var err: Int32

    repeat {
        let name = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0];
        let namePointer = name.withUnsafeBufferPointer { UnsafeMutablePointer<Int32>(mutating: $0.baseAddress) }
        var length: Int = 0
        
        err = sysctl(namePointer, u_int(name.count), nil, &length, nil, 0)
        if err == -1 {
            err = errno
        }
    
        if err == 0 {
            let count = length / MemoryLayout<kinfo_proc>.stride
            result =  [kinfo_proc](repeating: kinfo_proc(), count: count)
            err = result!.withUnsafeMutableBufferPointer({ ( p: inout UnsafeMutableBufferPointer<kinfo_proc>) -> Int32 in
                return sysctl(namePointer, u_int(name.count), p.baseAddress, &length, nil, 0)
            })
            switch err {
            case 0:
                done = true
            case -1:
                err = errno
            case ENOMEM:
                err = 0
            default:
                fatalError()
            }
        }
    } while err == 0 && !done

    return result
}

// NOTE: sysctl kp_proc.p_comm char array only stores first 16 characters of process name, so remember that when searching for a process using its name
public func isProcessRunning(executableName: String) -> Bool { //processes: [kinfo_proc]?
    let processes = GetBSDProcessList()!
    for process in processes {
        let name = withUnsafePointer(to: process.kp_proc.p_comm) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                String(cString: $0)
            }
        }
        if name == executableName {
            return true
        }
    }
    return false
}
