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
