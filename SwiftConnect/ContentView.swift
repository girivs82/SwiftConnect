//
//  ContentView.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import SwiftUI

let windowSize = CGSize(width: 250, height: 250)
let windowInsets = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView();
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .popover
        return visualEffect
    }
    
    func updateNSView(_ nsView: NSView, context: Context) { }
}

struct VPNApprovalScreen: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var settings_help_message: SettingsHelpMessage
    
    var body: some View {
        VStack {
            Text($settings_help_message.helpMessage.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(100)
        }
    }
}

struct VPNStuckScreen: View {
    @EnvironmentObject var settings_help_message: SettingsHelpMessage
    
    var body: some View {
        VStack {
            Text("Openconnect Bad State Notice")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(100)
            Spacer().frame(height: 25)
            Text($settings_help_message.helpMessage.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(100)
        }
    }
}

struct VPNLaunchedScreen: View {
    @EnvironmentObject var credentials: Credentials
    @EnvironmentObject var vpn: VPNController
    
    var body: some View {
            VStack {
                Image("Connected")
                    .resizable()
                    .scaledToFit()
                Text("🌐 VPN Connected!")
                Spacer().frame(height: 25)
                Button(action: { vpn.terminate() }) {
                    Text("Disconnect")
                }.keyboardShortcut(.defaultAction)
        }
    }
}

struct VPNLoginScreen: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var credentials: Credentials
    @EnvironmentObject var network: NetworkPathMonitor
    @Environment(\.colorScheme) var colorScheme
    @State private var useSAMLv2 = true
    @State var openconnectPath = "Openconnect Binary Path"
    @State var showFileChooser = false
    
    var body: some View {
        VStack {
            Group {
                Picker(selection: $vpn.proto, label: EmptyView()) {
                    ForEach(VPNProtocol.allCases, id: \.self) {
                        Text($0.name)
                    }
                }
                Picker(selection: $credentials.portal, label: EmptyView()) {
                    ForEach(AppDelegate.shared.serverlist, id: \.self.id) {
                        Text($0.serverName)
                    }
                }
                HStack {
                    Text("VPN Interface")
                    TextField("Interface", text: $credentials.intf ?? "")
                }
            }
            Group {
                HStack {
                    Text("Username")
                    TextField("Username", text: $credentials.username ?? "")
                }
                HStack {
                    Text("Password")
                    SecureField("Password", text: $credentials.password ?? "")
                }
            }
            Group {
                Toggle(isOn: $useSAMLv2) {
                    Text("SAMLv2")
                }
                .toggleStyle(CheckboxToggleStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack {
                    Button(action:
                    {
                        let panel = NSOpenPanel()
                        panel.resolvesAliases = false
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK {
                            let alert = NSAlert()
                            alert.messageText = "Trusted Binary Notice"
                            alert.informativeText = "Please ensure that the binary selected is trusted. It will be run with elevated privileges."
                            alert.runModal()
                            credentials.bin_path = panel.url?.path ?? ""
                        }
                    }, label: { Text($credentials.bin_path.wrappedValue ?? "").frame(maxWidth: .infinity) })
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: {
                if canReachServer(server: self.credentials.portal) {
                    self.credentials.samlv2 = self.useSAMLv2
                    vpn.start()
                }
                else {
                    let alert = NSAlert()
                    alert.messageText = "Cannot reach vpn gateway"
                    alert.informativeText = "The requested vpn gateway \(self.credentials.portal) is unreachable. Either the gateway is down or check your network settings."
                    alert.runModal()
                }
            }) {
                Text("Connect")
            }.keyboardShortcut(.defaultAction)
                .disabled(self.credentials.portal.isEmpty || self.credentials.intf!.isEmpty || self.credentials.username!.isEmpty || self.credentials.password!.isEmpty || self.credentials.bin_path! == "Select openconnect path")
        }
    }
}

struct VPNLoginScreen_Previews: PreviewProvider {

    static var previews: some View {
        VPNLoginScreen()
    }
}

struct VPNWebAuthScreen: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var credentials: Credentials
    @ObservedObject var model: WebViewModel
    @State private var saveToKeychain = false
    @State private var useSAMLv2 = true
    
    init(mesgURL: URL) {
        self.model = WebViewModel(link: mesgURL)
        }
    
    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Button(action: {
                    vpn.state = .stopped
                    AppDelegate.shared.pinPopover = false
                }) {
                    Text("Cancel Authentication")
                }
                Spacer()
                //The title of the webpage
                Text(self.model.didFinishLoading ? self.model.pageTitle : "")
                Spacer()
            }
            //The webpage itself
            AuthWebView(viewModel: model)
        }
            .padding(5.0)
    }
}

struct VPNWebAuthScreen_Previews: PreviewProvider {

    static var previews: some View {
        VPNWebAuthScreen(mesgURL: URL(string: "")!)
    }
}


struct ContentView: View {
    @EnvironmentObject var credentials : Credentials
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var settings_help_message: SettingsHelpMessage
    
    var body: some View {
        VStack {
            switch (vpn.state) {
            case .approval: VPNApprovalScreen().frame(width: windowSize.width, height: windowSize.height)
            case .stopped: VPNLoginScreen().frame(width: windowSize.width, height: windowSize.height)
            case .webauth: VPNWebAuthScreen(mesgURL: URL(string: self.credentials.preauth!.login_url!)!).frame(width: 480, height: 650)
            case .processing: ProgressView().frame(width: windowSize.width, height: windowSize.height)
            case .launched: VPNLaunchedScreen().frame(width: windowSize.width, height: windowSize.height)
            case .stuck: VPNStuckScreen().frame(width: windowSize.width, height: windowSize.height)
            }
        }
        .padding(windowInsets)
        .background(VisualEffect())
        .environmentObject(credentials)
        .environmentObject(vpn)
        .environmentObject(settings_help_message)
    }
    
    static let inPreview: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1";
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
