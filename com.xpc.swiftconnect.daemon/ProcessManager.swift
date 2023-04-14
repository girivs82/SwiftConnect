//
//  ProcessManager.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 18/07/22.
//

import Foundation
import Darwin
import os.log

typealias CompletionHandler = (_ result: Result<Int32, Error>, _ output: Data) -> Void

class ProcessManager {
    private var proc: Process?
    public var openconnect_status: Bool = false
    static let shared = ProcessManager()
    
    public func isProcRunning() -> Bool {
        return ((self.proc?.isRunning) != nil)
    }
    
    public func terminateProcess() -> Void {
        self.proc?.terminate()
        self.proc?.waitUntilExit()
    }
    
    /// Modified from: https://developer.apple.com/forums/thread/690310
    /// Runs the specified tool as a child process, supplying `stdin` and capturing `stdout`.
    ///
    /// - important: Must be run on the main queue.
    ///
    /// - Parameters:
    ///   - tool: The tool to run.
    ///   - arguments: The command-line arguments to pass to that tool; defaults to the empty array.
    ///   - input: Data to pass to the tool’s `stdin`; defaults to empty.
    ///   - completionHandler: Called on the main queue when the tool has terminated.

    func launch(tool: URL, arguments: [String] = [], input: Data = Data(), completionHandler: @escaping CompletionHandler) {
        // This precondition is important; read the comment near the `run()` call to
        // understand why.
        dispatchPrecondition(condition: .onQueue(.main))

        let group = DispatchGroup()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        var errorQ: Error? = nil
        var output = Data()
        var err = Data()
        var stdoutLines : String = ""
        var stderrLines : String = ""
        Logger.openconnect.info("\(tool, privacy: .public), \(arguments, privacy: .public)")
        self.proc = Process()
        self.proc?.executableURL = tool
        self.proc?.arguments = arguments
        self.proc?.standardInput = inputPipe
        self.proc?.standardOutput = outputPipe
        self.proc?.standardError = errorPipe
        // Prepare an environment as close to a new macOS user account as possible
        let cleanenvvars = ["TERM_PROGRAM", "SHELL", "TERM", "TMPDIR", "Apple_PubSub_Socket_Render", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "USER", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING", "XPC_FLAGS", "XPC_SERVICE_NAME", "SHLVL", "HOME", "LOGNAME", "LC_CTYPE", "_"]
        self.proc?.environment = cleanenvvars.reduce(into: [String: String]()) { $0[$1] = "" }
        self.proc?.environment!["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        group.enter()
        self.proc?.terminationHandler = { _ in
            // This bounce to the main queue is important; read the comment near the
            // `run()` call to understand why.
            DispatchQueue.main.async {
                group.leave()
            }
        }

        // This runs the supplied block when all three events have completed (task
        // termination and the end of both I/O channels).
        //
        // - important: If the process was never launched, requesting its
        // termination status raises an Objective-C exception (ouch!).  So, we only
        // read `terminationStatus` if `errorQ` is `nil`.

        group.notify(queue: .main) {
            if let error = errorQ {
                completionHandler(.failure(error), output)
            } else {
                completionHandler(.success(self.proc?.terminationStatus ?? -1), output)
            }
        }
        
        do {
            func posixErr(_ error: Int32) -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil) }

            // If you write to a pipe whose remote end has closed, the OS raises a
            // `SIGPIPE` signal whose default disposition is to terminate your
            // process.  Helpful!  `F_SETNOSIGPIPE` disables that feature, causing
            // the write to fail with `EPIPE` instead.
            
            let fcntlResult = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            guard fcntlResult >= 0 else { throw posixErr(errno) }

            // Actually run the process.
            
            try self.proc?.run()
            
            // At this point the termination handler could run and leave the group
            // before we have a chance to enter the group for each of the I/O
            // handlers.  I avoid this problem by having the termination handler
            // dispatch to the main thread.  We are running on the main thread, so
            // the termination handler can’t run until we return, at which point we
            // have already entered the group for each of the I/O handlers.
            //
            // An alternative design would be to enter the group at the top of this
            // block and then leave it in the error hander.  I decided on this
            // design because it has the added benefit of all my code running on the
            // main queue and thus I can access shared mutable state, like `errorQ`,
            // without worrying about thread safety.
            
            // Enter the group and then set up a Dispatch I/O channel to write our
            // data to the child’s `stdin`.  When that’s done, record any error and
            // leave the group.
            //
            // Note that we ignore the residual value passed to the
            // `write(offset:data:queue:ioHandler:)` completion handler.  Earlier
            // versions of this code passed it along to our completion handler but
            // the reality is that it’s not very useful. The pipe buffer is big
            // enough that it usually soaks up all our data, so the residual is a
            // very poor indication of how much data was actually read by the
            // client.

            group.enter()
            let writeIO = DispatchIO(type: .stream, fileDescriptor: inputPipe.fileHandleForWriting.fileDescriptor, queue: .main) { _ in
                // `FileHandle` will automatically close the underlying file
                // descriptor when you release the last reference to it.  By holidng
                // on to `inputPipe` until here, we ensure that doesn’t happen. And
                // as we have to hold a reference anyway, we might as well close it
                // explicitly.
                //
                // We apply the same logic to `readIO` below.
                try! inputPipe.fileHandleForWriting.close()
            }
            let inputDD = input.withUnsafeBytes { DispatchData(bytes: $0) }
            writeIO.write(offset: 0, data: inputDD, queue: .main) { isDone, _, error in
                if isDone || error != 0 {
                    writeIO.close()
                    if errorQ == nil && error != 0 { errorQ = posixErr(error) }
                    group.leave()
                }
            }

            // Enter the group and then set up a Dispatch I/O channel to read data
            // from the child’s `stdin`.  When that’s done, record any error and
            // leave the group.

            group.enter()
            let readIO = DispatchIO(type: .stream, fileDescriptor: outputPipe.fileHandleForReading.fileDescriptor, queue: .main) { _ in
                try! outputPipe.fileHandleForReading.close()
            }
            readIO.setLimit(lowWater: 1)
            readIO.setLimit(highWater: 64)
            readIO.read(offset: 0, length: .max, queue: .main) { isDone, chunkQ, error in
                let d = chunkQ as AnyObject as! Data
                let d_str = String(decoding: d, as: UTF8.self)
                stdoutLines = stdoutLines + d_str
                var outArray = stdoutLines.split(whereSeparator: \.isNewline)
                if !stdoutLines.hasSuffix("\n") && !outArray.isEmpty {
                    outArray.removeLast()
                }
                if let index = stdoutLines.lastIndex(of: "\n") {
                    stdoutLines = String(stdoutLines.suffix(from: index).dropFirst())
                }
                for line in outArray {
                    Logger.openconnect.info("\(line, privacy: .public)")
                    // Identify DTLS connection
                    if line.hasPrefix("Established DTLS connection") {
                        self.openconnect_status = true
                        Logger.openconnect.info("Openconnect Connection is Good: \(self.openconnect_status)")
                    }
                }
                output.append(contentsOf: chunkQ ?? .empty)
                if isDone || error != 0 {
                    readIO.close()
                    if errorQ == nil && error != 0 { errorQ = posixErr(error) }
                    group.leave()
                }
            }
            
            //Do the same for the error pipe
            group.enter()
            let errorIO = DispatchIO(type: .stream, fileDescriptor: errorPipe.fileHandleForReading.fileDescriptor, queue: .main) { _ in
                try! errorPipe.fileHandleForReading.close()
            }
            errorIO.setLimit(lowWater: 1)
            errorIO.setLimit(highWater: 64)
            errorIO.read(offset: 0, length: .max, queue: .main) { isDone, chunkQ, error in
                let d = chunkQ as AnyObject as! Data
                let d_str = String(decoding: d, as: UTF8.self)
                stderrLines = stderrLines + d_str
                var errArray = stderrLines.split(whereSeparator: \.isNewline)
                if !stderrLines.hasSuffix("\n") && !errArray.isEmpty {
                    errArray.removeLast()
                }
                if let index = stderrLines.lastIndex(of: "\n") {
                    stderrLines = String(stderrLines.suffix(from: index).dropFirst())
                }
                for line in errArray {
                    Logger.openconnect.error("\(line, privacy: .public)")
                    // Identify DTLS handshake failure
                    if line.hasPrefix("Failed to reconnect to host") || line.hasPrefix("DTLS Dead Peer Detection detected dead peer!") || line.hasPrefix("DTLS handshake failed") {
                        self.openconnect_status = false
                        Logger.openconnect.info("Openconnect Connection is Good: \(self.openconnect_status)")
                    }
                }
                err.append(contentsOf: chunkQ ?? .empty)
                if isDone || error != 0 {
                    errorIO.close()
                    if errorQ == nil && error != 0 { errorQ = posixErr(error) }
                    group.leave()
                }
            }
        } catch {
            // If either the `fcntl` or the `run()` call threw, we set the error
            // and manually call the termination handler.  Note that we’ve only
            // entered the group once at this point, so the single leave done by the
            // termination handler is enough to run the notify block and call the
            // client’s completion handler.
            errorQ = error
            self.proc?.terminationHandler!(self.proc!)
        }
    }
}
