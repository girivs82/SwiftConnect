//
//  WebView.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 24/06/22.
//

import SwiftUI
import WebKit
import Combine

class WebViewModel: ObservableObject {
    @Published var link: URL?
    @Published var didFinishLoading: Bool = false
    @Published var pageTitle: String
    
    init (link: URL) {
        self.link = link
        self.pageTitle = ""
    }
}

struct AuthWebView: NSViewRepresentable {
    
    public typealias NSViewType = WKWebView
    @ObservedObject var viewModel: WebViewModel
    @EnvironmentObject var credentials: Credentials
    
    
    private let webView: WKWebView = WKWebView(frame: .zero)
    public func makeNSView(context: NSViewRepresentableContext<AuthWebView>) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator as? WKUIDelegate
        
        let request = URLRequest(url: viewModel.link!)
        webView.load(request)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: NSViewRepresentableContext<AuthWebView>) { }

    public func makeCoordinator() -> Coordinator {
        return Coordinator(viewModel, credentials: credentials)
    }
    
}
    
class Coordinator: NSObject, WKNavigationDelegate {
    private var viewModel: WebViewModel
    private var credentials: Credentials
    
    init(_ viewModel: WebViewModel, credentials: Credentials) {
        //Initialise the WebViewModel
        self.viewModel = viewModel
        self.credentials = credentials
    }
    
    public func webView(_: WKWebView, didFail: WKNavigation!, withError: Error) { }

    public func webView(_: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError: Error) { }
    
    private func getCookie(web: WKWebView, name: String?) -> Void {
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                if (cookie.name == name) {
                    self.credentials.samlv2Token = cookie
                    //Use GCD to invoke the completion handler on the main thread
                    DispatchQueue.main.async() {
                        self.credentials.authCookieCallback!(cookie)
                    }
                    break
                }
            }
        }
    }

    //After the webpage is loaded, assign the data in WebViewModel class
    public func webView(_ web: WKWebView, didFinish: WKNavigation!) {
        self.viewModel.pageTitle = web.title!
        self.viewModel.link = web.url!
        self.viewModel.didFinishLoading = true
        if web.url?.absoluteString == self.credentials.preauth?.login_final_url {
            self.getCookie(web: web, name: self.credentials.preauth?.token_cookie_name)
        }
    }

    func webView(_ web: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { }

    func webView(_ web: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if(navigationAction.navigationType == .other) {
                    if let redirectedUrl = navigationAction.request.url {
                        
                        //After redirect
                    }
                    
                }
        decisionHandler(.allow)
    }
    
    func webView(_ web: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            let headers = response.allHeaderFields
        }
        decisionHandler(.allow)
    }

}

