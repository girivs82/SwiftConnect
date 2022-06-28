//
//  ContentView.swift
//  SwiftConnect
//
//  Created by Wenyu Zhao on 8/12/2021.
//

import SwiftUI

let windowSize = CGSize(width: 200, height: 230)
let windowInsets = EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30)

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

struct VPNLaunchedScreen: View {
    @EnvironmentObject var vpn: VPNController
    
    var body: some View {
        ZStack {
            VStack {
                Image("Connected")
                    .resizable()
                    .scaledToFit()
                Text("🌐 VPN Connected!")
                Spacer().frame(height: 25)
                Button(action: { vpn.kill() }) {
                    Text("Disconnect")
                }.keyboardShortcut(.defaultAction)
        }
        Button(action: { vpn.openLogFile() }) {
            Text("logs").underline()
                .foregroundColor(Color.gray)
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(PlainButtonStyle())
                .position(x: 155, y: 190)
        }
        .environmentObject(vpn)
    }
}

struct VPNLaunchedScreen_Previews: PreviewProvider {
    static var previews: some View {
        VPNLaunchedScreen()
            .padding(windowInsets)
            .frame(width: windowSize.width, height: windowSize.height).background(VisualEffect())
            .environmentObject(VPNController())
    }
}

struct VPNProgressingScreen: View {
    @EnvironmentObject var vpn: VPNController
    
    var body: some View {
            VStack {
                Text("Connecting...")
                Spacer().frame(height: 25)
                Button(action: { vpn.kill() }) {
                    Text("Disconnect")
                }.keyboardShortcut(.defaultAction)
        }
        .environmentObject(vpn)
    }
}

struct VPNProgressingScreen_Previews: PreviewProvider {
    static var previews: some View {
        VPNProgressingScreen().environmentObject(VPNController())
    }
}

struct VPNLoginScreen: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var credentials: Credentials
    @State private var saveToKeychain = false
    @State private var useSAMLv2 = true
    
    var body: some View {
        VStack {
            Picker(selection: $vpn.proto, label: EmptyView()) {
                ForEach(VPNProtocol.allCases, id: \.self) {
                    Text($0.name)
                }
            }
            TextField("Portal", text: $credentials.portal)
            if !useSAMLv2 {
                TextField("Username", text: $credentials.username)
                SecureField("Password", text: $credentials.password).onSubmit {
                    vpn.start(credentials: credentials, save: saveToKeychain)
                }
            }
            Toggle(isOn: $saveToKeychain) {
                Text("Save to Keychain")
            }.toggleStyle(CheckboxToggleStyle())
            Spacer().frame(height: 25)
            Toggle(isOn: $useSAMLv2) {
                Text("SAMLv2")
            }.toggleStyle(CheckboxToggleStyle())
            Spacer().frame(height: 25)
            Button(action: {
                self.credentials.samlv2 = self.useSAMLv2
                vpn.start(credentials: credentials, save: saveToKeychain)
            }) {
                Text("Connect")
            }.keyboardShortcut(.defaultAction)
             .disabled(!useSAMLv2)
        }
    }
}

struct VPNLoginScreen_Previews: PreviewProvider {
    
    static var previews: some View {
        VPNLoginScreen().environmentObject(VPNController()).environmentObject(Credentials())
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
                Spacer()
                Spacer()
                //The title of the webpage
                Text(self.model.didFinishLoading ? self.model.pageTitle : "")
                Spacer()
                //The "Open with Safari" button on the top right side of the preview
                Button(action: {
                    if let url = self.model.link {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Open with Safari")
                }
            }
            //The webpage itself
            AuthWebView(viewModel: model)
        }.frame(width: 800, height: 450, alignment: .bottom)
            .padding(5.0)

    }
}

struct VPNWebAuthScreen_Previews: PreviewProvider {
    
    static var previews: some View {
        VPNWebAuthScreen(mesgURL: URL(string: "")!).environmentObject(VPNController()).environmentObject(Credentials())
    }
}


struct ContentView: View {
    @StateObject var vpn = VPNController()
    @StateObject var credentials = Credentials()
    
    var body: some View {
        VStack {
            switch vpn.state {
            case .stopped: VPNLoginScreen().frame(width: windowSize.width, height: windowSize.height)
            case .webauth: VPNWebAuthScreen(mesgURL: URL(string: self.credentials.preauth!.login_url!)!).frame(width: 800, height: 450)
            case .processing: ProgressView().frame(width: windowSize.width, height: windowSize.height)
            case .launched: VPNLaunchedScreen().frame(width: windowSize.width, height: windowSize.height)
            }
        }
        .padding(windowInsets)
        .background(VisualEffect())
        .environmentObject(vpn)
        .environmentObject(credentials)
    }
}

struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        ContentView().environmentObject(VPNController()).environmentObject(Credentials())
    }
}
