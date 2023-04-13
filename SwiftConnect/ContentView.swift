//
//  ContentView.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import SwiftUI

let windowSize = CGSize(width: 250, height: 400)
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

struct VPNLogScreen: View {
    @EnvironmentObject var vpn: VPNController
    @State private var logtext: String = ""
    
    var body: some View {
        VStack {
            TextEditor(text: $logtext)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(100)
            Spacer().frame(height: 25)
            Button(action: {
                readLogEntries(category: "openconnect") { result in
                logtext = result
                }
            }) { Text("Show Logs").frame(maxHeight: 25) }
            Spacer().frame(height: 25)
            Button(action: { vpn.state = .launched  }) { Text("Back").frame(maxHeight: 25) }
        }
    }
}

struct VPNLaunchedScreen: View {
    @EnvironmentObject var credentials: Credentials
    @EnvironmentObject var vpn: VPNController
    
    var body: some View {
        ZStack {
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
            Button(action: { vpn.state = .viewlogs }) {
            Text("logs").underline()
                .foregroundColor(Color.gray)
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(PlainButtonStyle())
                .position(x: 155, y: 190)
        }
    }
}

struct VPNLoginScreen: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var credentials: Credentials
    @EnvironmentObject var network: NetworkPathMonitor
    @Environment(\.colorScheme) var colorScheme
    @State private var saveToKeychain = true
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
            }
            Group {
                Spacer().frame(height: 25)
                Text("Username")
                TextField("Username", text: $credentials.username ?? "")
                Text("Password")
                SecureField("Password", text: $credentials.password ?? "")
            }
            Spacer().frame(height: 25)
            Toggle(isOn: $saveToKeychain) {
                Text("Save to Keychain")
            }.toggleStyle(CheckboxToggleStyle())
            Toggle(isOn: $useSAMLv2) {
                Text("SAMLv2")
            }.toggleStyle(CheckboxToggleStyle())
            Spacer().frame(height: 25)
            VStack {
                Text("Openconnect Bin Path")
                TextField("Openconnect path", text: $credentials.bin_path ?? "")
                    .disabled(true)
                    .foregroundColor(colorScheme == .light ? .black : .white)
                Button("Select")
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
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Spacer().frame(height: 25)
            Button(action: {
                if canReachServer(server: self.credentials.portal) {
                    self.credentials.samlv2 = self.useSAMLv2
                    vpn.start(credentials: credentials, save: saveToKeychain)
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
                .disabled(self.credentials.portal.isEmpty || self.credentials.username!.isEmpty || self.credentials.password!.isEmpty || self.credentials.bin_path!.isEmpty)
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
    @StateObject var credentials : Credentials = AppDelegate.shared.credentials!
    @StateObject var vpn : VPNController = VPNController.shared
    
    init(forceState: VPNState? = nil) {
        _credentials = StateObject(wrappedValue: Credentials())
    }
    
    var body: some View {
        VStack {
            switch (vpn.state) {
            case .stopped: VPNLoginScreen().frame(width: windowSize.width, height: windowSize.height)
            case .webauth: VPNWebAuthScreen(mesgURL: URL(string: self.credentials.preauth!.login_url!)!).frame(width: 480, height: 650)
            case .processing: ProgressView().frame(width: windowSize.width, height: windowSize.height)
            case .launched: VPNLaunchedScreen().frame(width: windowSize.width, height: windowSize.height)
            case .viewlogs: VPNLogScreen().frame(width: 480, height: 650)
            }
        }
        .padding(windowInsets)
        .background(VisualEffect())
        .environmentObject(credentials)
        .environmentObject(vpn)
    }
    
    static let inPreview: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1";
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(forceState: VPNState.processing)
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
