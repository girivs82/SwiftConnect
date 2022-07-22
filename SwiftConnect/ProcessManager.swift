//
//  ProcessManager.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 18/07/22.
//

import Foundation
import Darwin
import os.log

class ProcessManager {
    private var proc_name : String?
    private var pid_file_path : URL?
    static let shared = ProcessManager()
    
    public func initialize(proc_name: String?, pid_file: URL?) {
        self.proc_name = proc_name
        self.pid_file_path = pid_file
    }
    
    fileprivate func GetBSDProcessList() -> ([kinfo_proc]?)  {

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
    fileprivate func isProcessRunning(executableName: String, proc_id: Int32) -> Bool { //processes: [kinfo_proc]?
        let processes = GetBSDProcessList()!
        for process in processes {
            let name = withUnsafePointer(to: process.kp_proc.p_comm) {
                $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                    String(cString: $0)
                }
            }
            if name == executableName {
                let p_pid = process.kp_proc.p_pid
                if p_pid == proc_id {
                    return true
                }
            }
        }
        return false
    }

    fileprivate func getPID() -> Int32 {
        var pid : Int32 = -1
        do {
            let strPID = try String(contentsOf: self.pid_file_path!, encoding: String.Encoding.utf8).trimmingCharacters(in: ["\n"])
            pid = Int32(strPID)!
        }
        catch {

        }
        return  pid
    }
    
    public func isProcRunning() -> Bool {
        let pid = getPID()
        return isProcessRunning(executableName: proc_name!, proc_id: pid)
    }
    
    public func terminateProcess(credentials: Credentials?) -> Void {
        let pid = getPID()
        if isProcessRunning(executableName: proc_name!, proc_id: pid) {
            launch(tool: URL(fileURLWithPath: "/usr/bin/sudo"),
                   arguments: ["-k", "-S", "kill", String(pid)],
                   input: Data("\(credentials!.sudo_password!)\n".utf8)) { status, output in
                Logger.vpnProcess.info("[\(self.proc_name!)] completed")
                }
        }
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
        
        var errorQ: Error? = nil
        var output = Data()

        let proc = Process()
        proc.executableURL = tool
        proc.arguments = arguments
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        // Prepare an environment as close to a new OS X user account as possible with the exception of PATH variable, where /opt/homebrew/bin is also added to discover openconnect
        let cleanenvvars = ["TERM_PROGRAM", "SHELL", "TERM", "TMPDIR", "Apple_PubSub_Socket_Render", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "USER", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING", "XPC_FLAGS", "XPC_SERVICE_NAME", "SHLVL", "HOME", "LOGNAME", "LC_CTYPE", "_"]
        proc.environment = cleanenvvars.reduce(into: [String: String]()) { $0[$1] = "" }
        proc.environment!["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        group.enter()
        proc.terminationHandler = { _ in
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
                completionHandler(.success(proc.terminationStatus), output)
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
            
            try proc.run()
            
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
                print("\(d_str)", terminator:"")
                output.append(contentsOf: chunkQ ?? .empty)
                if isDone || error != 0 {
                    readIO.close()
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
            proc.terminationHandler!(proc)
        }
    }
}
