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
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate!;
    static var network_dropped: Bool = false
    static var open_settings: Bool = false
    static var network_monitor = NetworkPathMonitor.shared
    private var credentials: Credentials = Credentials()
    private var vpn: VPNController = VPNController()
    private var settings_help_message: SettingsHelpMessage = SettingsHelpMessage()
    var serverlist = [Server]()
    
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
        let contentView = ContentView().environmentObject(credentials).environmentObject(vpn).environmentObject(settings_help_message)
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
        statusItem.button?.image?.isTemplate = !connected || AppDelegate.network_dropped
        vpn.state = connected ? .launched : .stopped
    }
    
    func networkDidDrop(dropped: Bool) {
        statusItem.button?.image = icon_connected
        statusItem.button?.image?.isTemplate = dropped
        if dropped {
            generateNotification(sound: "NO", title: "Gateway connection failed", body: "openconnect lost connection to the gateway. Please troubleshoot your network.")
        } else {
            generateNotification(sound: "NO", title: "Gateway connection restored", body: "openconnect vpn connection restored.")
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self;
        // Hide app window
        NSApplication.shared.windows.first?.close()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if ContentView.inPreview {
            return;
        }
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)
        // Hide app window
        if let window = NSApplication.shared.windows.first {
            window.close()
        }
        self.serverlist = load_gateways_from_plist(plist_name: "ngvpn")
        // Just initialize the vpncontroller, so that credentials can be passed to it as early as possible
        vpn.initialize(credentials: credentials)
        // Periodically poll for status changes until daemon is enabled
        Commands.status_change_check()
        // Initialize statusItem
        statusItem.button!.target = self
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        DispatchQueue.main.async {
            Commands.terminate()
            Commands.disable_conn_check()
            Commands.unregister()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.terminate(nil)
        }
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
    
    func setAppServiceState() -> SMAppService.Status {
        let status = Commands.status()
        switch status {
        case .notRegistered:
            self.settings_help_message.helpMessage = "Please wait..."
            Commands.register()
            AppDelegate.open_settings = false
        case .enabled:
            self.settings_help_message.helpMessage = "If you see this, its a bug. Report this."
            Commands.register()
            self.vpn.state = .stopped
            AppDelegate.open_settings = false
        case .requiresApproval:
            self.settings_help_message.helpMessage = "Approve SwiftConnect in Settings->General->Login Items in System Settings which has been opened for you. You can also approve in the notification banner if it shows up in the notifications area of your screen."
            if !AppDelegate.open_settings {
                Commands.settings()
                AppDelegate.open_settings = true
            }
        case .notFound:
            Commands.register()
            self.settings_help_message.helpMessage = "Please approve the launch daemon request so that openconnect can be run via the daemon with elevated privileges in System Settings. Check your notification area."
            AppDelegate.open_settings = false
        @unknown default:
            AppDelegate.open_settings = false
            break
        }
        return status
    }
    
    func vpnBadState() {
        DispatchQueue.main.async {
            self.settings_help_message.helpMessage = "Openconnect process is in a bad state and refuses to die. Please quit SwiftConnect and then try to kill the openconnect process yourself."
        }
    }
    
    func generateNotification (sound:String, title:String , body:String) {
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
            Commands.terminate()
            Commands.disable_conn_check()
            Commands.unregister()
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
