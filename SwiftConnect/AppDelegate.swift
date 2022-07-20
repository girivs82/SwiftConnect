//
//  AppDelegate.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import Cocoa
import SwiftUI
import UserNotifications
import os.log


class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate!;
    
    var pinPopover = false
    
    private lazy var icon: NSImage = {
        let image = NSImage(named: "AppIcon")!
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
    private lazy var icon_connected: NSImage = {
        let image = NSImage(named: "Connected")!
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 200, height: 200)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        popover.delegate = self
        return popover
    }()
    private lazy var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = icon
        statusItem.button?.image?.isTemplate = true
        statusItem.button!.action = #selector(togglePopover(sender:))
        statusItem.button!.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return statusItem
    }()
    private lazy var contextMenu: ContextMenu = ContextMenu(statusBarItem: statusItem)
    
    func vpnConnectionDidChange(connected: Bool) {
        statusItem.button?.image = (connected) ? icon_connected : icon
        statusItem.button?.image?.isTemplate = !connected
        //popover.contentViewController.
        //generateNotification(sound: "NO", title: (connected) ? "VPN Connected" : "VPN Disconnected", body: (connected) ? "VPN is now connected." : "VPN is now disconnected.")
    }
    
    func networkDidDrop(dropped: Bool) {
//        statusItem.button?.image?.isTemplate = dropped
//        if dropped {
//            generateNotification(sound: "NO", title: "Network unreachable", body: "The network is unreachable. Please troubleshoot your network.")
//        } else {
//            generateNotification(sound: "NO", title: "Network available", body: "The network is reachable.")
//        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self;
        // Hide app window
        NSApplication.shared.windows.first?.close()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)
        // Hide app window
        if let window = NSApplication.shared.windows.first {
            window.close()
        }
        // Just instantiate the shared objects for processmanager and networkpathmonitor here for them to run early
        ProcessManager.shared.initialize(proc_name: "openconnect", pid_file: URL(string: "file:///var/run/openconnect.pid"))
        _ = NetworkPathMonitor.shared
        // Initialize statusItem
        statusItem.button!.target = self
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func popoverWillShow(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return !pinPopover
    }
    
    @objc func togglePopover(sender: AnyObject) {
        if NSApp.currentEvent!.type ==  NSEvent.EventType.leftMouseUp {
            if (popover.isShown) {
                closePopover()
            } else {
                openPopover()
            }
        } else {
            contextMenu.show()
        }
    }
    
    func openPopover() {
        popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: NSRectEdge.maxY)
    }
    
    func closePopover() {
        popover.performClose(self)
    }
    
    func testPrivilege() -> Bool {
        return getuid() == 0;
    }
    
    func generateNotification (sound:String, title:String , body:String) {
        if #available(OSX 10.14, *) {
            UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared // must have delegate, otherwise notification won't appear
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                guard granted else { return }
                let notificationCenter = UNUserNotificationCenter.current()
                notificationCenter.getNotificationSettings
                   { (settings) in
                    if settings.authorizationStatus == .authorized {
                        // build the banner
                        let content = UNMutableNotificationContent();
                        content.title = title
                        content.body = body
                        if sound == "YES" {content.sound =  UNNotificationSound.default};
                        // define when banner will appear - this is set to 1 seconds - note you cannot set this to zero
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false);
                        // Create the request
                        let uuidString = UUID().uuidString ;
                        let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger);
                        // Schedule the request with the system.
                        notificationCenter.add(request, withCompletionHandler:
                            { (error) in
                            if error != nil
                                {
                                    // Something went wrong
                                    Logger.viewCycle.error("Something went wrong while adding notifications!")
                                }
                            })
                    }
                }
            }
            
        } else {
            // Fallback on earlier versions
            Logger.viewCycle.error("Notifications not implemented for macOS < 10.14")
        }
    }
}


class ContextMenu: NSObject, NSMenuDelegate {
    let statusBarItem: NSStatusItem

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Status Bar Menu")
        menu.delegate = self
        // Title
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
        let title = menu.addItem(
            withTitle: "SwiftConnect v\(appVersion)",
            action: #selector(self.openProjectURL(_:)),
            keyEquivalent: ""
        )
        title.image = NSImage(named: "AppIcon")!
        title.image?.isTemplate = true
        title.target = self
        // Separator
        menu.addItem(NSMenuItem.separator())
        // Quit button
        let qitem = menu.addItem(
            withTitle: "⎋ Quit",
            action: #selector(self.quit(_:)),
            keyEquivalent: "q"
        )
        qitem.target = self
        return menu
    }
    
    init(statusBarItem: NSStatusItem) {
        self.statusBarItem = statusBarItem
        super.init()
    }
    
    func show() {
        statusBarItem.menu = buildContextMenu()
        statusBarItem.button?.performClick(nil)
    }
    
    @objc func quit(_ sender: NSMenuItem) {
        DispatchQueue.main.async {
            ProcessManager.shared.terminateProcess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.terminate(nil)
        }
    }

    @objc func menuDidClose(_ menu: NSMenu) {
        statusBarItem.menu = nil
    }
    
    @objc func openProjectURL(_ menu: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/girivs82/SwiftConnect")!)
    }
}

class NotificationCenterDelegate : NSObject, UNUserNotificationCenterDelegate {
    static var shared: NotificationCenterDelegate!;
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // pull out the buried userInfo dictionary
        let userInfo = response.notification.request.content.userInfo

        if let _ = userInfo["customData"] as? String {

            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                // the user swiped to unlock
                break
            case "show":
                // the user tapped our "show more info…" button
                break
            default:
                break
            }
        }

        // you must call the completion handler when you're done
        completionHandler()
    }
}
