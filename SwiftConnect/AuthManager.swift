//
//  AuthManager.swift
//  saml-vpn-manager
//
//  Created by Shankar Giri Venkita Giri on 25/06/22.
//

import Foundation
import Network
import os.log

fileprivate extension URLRequest {
    func debug() {
        Logger.vpnProcess.debug("REQUEST")
        Logger.vpnProcess.debug("-------")
        Logger.vpnProcess.debug("\(self.httpMethod!) \(self.url!)")
        Logger.vpnProcess.debug("Headers:")
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(self.allHTTPHeaderFields) {
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.vpnProcess.debug("\(jsonString)")
            }
        }
        Logger.vpnProcess.debug("Body:")
        let httpbody = String(data: self.httpBody ?? Data(), encoding: .utf8)!
        Logger.vpnProcess.debug("\(httpbody)")
    }
}

fileprivate extension HTTPURLResponse {
    func debug() {
        Logger.vpnProcess.debug("RESPONSE")
        Logger.vpnProcess.debug("--------")
        Logger.vpnProcess.debug("\(self.url!)")
        Logger.vpnProcess.debug("Headers:")
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(self.allHeaderFields as! Dictionary<String,String>) {
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.vpnProcess.debug("\(jsonString)")
            }
        }
    }
}

struct AuthRequestResp {
    var auth_id: String?
    var auth_title: String?
    var auth_message: String?
    var auth_error: String?
    var login_url: String?
    var login_final_url: String?
    var token_cookie_name: String?
    var opaque: XMLElement = XMLElement(name: "opaque", stringValue:"")
}

struct AuthCompleteResp {
    var auth_id: String?
    var auth_message: String?
    var session_token: String?
    var server_cert_hash: String?
}

class AuthManager {
    private var credentials: Credentials?
    private var preAuthCallback: ((AuthRequestResp?) -> ())? = nil
    private var authCookieCallback: ((HTTPCookie?) -> ())? = nil
    private var postAuthCallback: ((AuthCompleteResp?) -> ())? = nil
    
    public init(credentials: Credentials?, preAuthCallback: @escaping ((AuthRequestResp?) -> Void), authCookieCallback: @escaping ((HTTPCookie?) -> Void), postAuthCallback: @escaping ((AuthCompleteResp?) -> Void)) {
        self.credentials = credentials
        self.preAuthCallback = preAuthCallback
        self.authCookieCallback = authCookieCallback
        self.postAuthCallback = postAuthCallback
        self.credentials?.preAuthCallback = preAuthCallback
        self.credentials?.authCookieCallback = authCookieCallback
        self.credentials?.postAuthCallback = postAuthCallback
    }
    
    public func pre_auth() {
        let authReq = self.createInitialAuthRequest()
        self.sendPreAuthRequest(request: authReq)
    }
    
    public func finish_auth(authReqResp: AuthRequestResp?, cookie: HTTPCookie?) {
        let authReq = self.createFinalAuthRequest(authReqResp: authReqResp)
        self.sendFinalAuthRequest(request: authReq)
    }
    
    private func createInitialAuthRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: self.credentials!.portal!)!)
        request.setValue("AnyConnect Linux_64 4.7.00136", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("1", forHTTPHeaderField: "X-Transcend-Version")
        request.setValue("1", forHTTPHeaderField: "X-Aggregate-Auth")
        request.setValue("true", forHTTPHeaderField: "X-Support-HTTP-Auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let config_auth =  XMLElement(name: "config-auth", stringValue:"")
        let httpbody = XMLDocument(rootElement: config_auth)
        httpbody.version = "1.0"
        httpbody.characterEncoding = "UTF-8"
        config_auth.addAttribute(XMLNode.attribute(withName: "client", stringValue: "vpn") as! XMLNode)
        config_auth.addAttribute(XMLNode.attribute(withName: "type", stringValue: "init") as! XMLNode)
        config_auth.addAttribute(XMLNode.attribute(withName: "aggregate-auth-version", stringValue: "2") as! XMLNode)
        let version = XMLElement(name: "version", stringValue:"4.7.00136")
        version.addAttribute(XMLNode.attribute(withName: "who", stringValue: "vpn") as! XMLNode)
        let device_id = XMLElement(name: "device-id", stringValue:"linux-64")
        let group_select =  XMLElement(name: "group-select", stringValue:"")
        let group_access =  (self.credentials!.samlv2) ? XMLElement(name: "group-access", stringValue:URL(string: "SAML", relativeTo: request.url)?.absoluteString) : XMLElement(name: "group-access", stringValue:request.url?.absoluteString)
        let capabilities =  XMLElement(name: "capabilities", stringValue:"")
        if self.credentials!.samlv2 {
            let auth_method =  XMLElement(name: "auth-method", stringValue:"single-sign-on-v2")
            capabilities.addChild(auth_method)
        }
        config_auth.addChild(version)
        config_auth.addChild(device_id)
        config_auth.addChild(group_select)
        config_auth.addChild(group_access)
        config_auth.addChild(capabilities)
        request.httpBody = httpbody.xmlString.data(using: .utf8)
        return request
    }
    
    private func createFinalAuthRequest(authReqResp: AuthRequestResp?) -> URLRequest {
        var request = URLRequest(url: URL(string: self.credentials!.portal!)!)
        request.setValue("AnyConnect Linux_64 4.7.00136", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("1", forHTTPHeaderField: "X-Transcend-Version")
        request.setValue("1", forHTTPHeaderField: "X-Aggregate-Auth")
        request.setValue("true", forHTTPHeaderField: "X-Support-HTTP-Auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let config_auth =  XMLElement(name: "config-auth", stringValue:"")
        let httpbody = XMLDocument(rootElement: config_auth)
        httpbody.version = "1.0"
        httpbody.characterEncoding = "UTF-8"
        config_auth.addAttribute(XMLNode.attribute(withName: "client", stringValue: "vpn") as! XMLNode)
        config_auth.addAttribute(XMLNode.attribute(withName: "type", stringValue: "auth-reply") as! XMLNode)
        config_auth.addAttribute(XMLNode.attribute(withName: "aggregate-auth-version", stringValue: "2") as! XMLNode)
        let version = XMLElement(name: "version", stringValue:"4.7.00136")
        version.addAttribute(XMLNode.attribute(withName: "who", stringValue: "vpn") as! XMLNode)
        let device_id = XMLElement(name: "device-id", stringValue:"linux-64")
        let session_token =  XMLElement(name: "session-token", stringValue:"")
        let session_id =  XMLElement(name: "session-id", stringValue:"")
        let auth =  XMLElement(name: "auth", stringValue:"")
        let sso_token = XMLElement(name: "sso-token", stringValue: self.credentials?.samlv2Token?.value)
        auth.addChild(sso_token)
        config_auth.addChild(version)
        config_auth.addChild(device_id)
        config_auth.addChild(session_token)
        config_auth.addChild(session_id)
        config_auth.addChild(authReqResp!.opaque)
        config_auth.addChild(auth)
        request.httpBody = httpbody.xmlString.data(using: .utf8)
        return request
    }
    
    func sendPreAuthRequest(request: URLRequest) -> Void {
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) {
            data,response,error in
            
            if let error = error {
                Logger.vpnProcess.error("Post Request Error: \(error.localizedDescription)")
              return
            }
            
            // ensure there is valid response code returned from this HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                Logger.vpnProcess.error("Invalid Response received from the server")
              return
            }
            
            // ensure there is data returned
            if data == nil {
                Logger.vpnProcess.error("nil Data received from the server")
              return
            }
//#if DEBUG
//            request.debug()
//            httpResponse.debug()
//#endif
            let parser = AuthRespParser(data: data!)
            var authResp: AuthRequestResp?
            if parser.parse() {
                authResp = parser.authResp
                self.credentials!.preauth = authResp
            } else {
                if let error = parser.parserError {
                    Logger.vpnProcess.error("\(error.localizedDescription)")
                } else {
                    Logger.vpnProcess.error("Failed with unknown reason")
                }
            }
            //Use GCD to invoke the completion handler on the main thread
            DispatchQueue.main.async() {
                self.preAuthCallback!(authResp)
            }
          }
          // perform the task
          task.resume()
    }
    
    func sendFinalAuthRequest(request: URLRequest) -> Void {        
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) {
            data,response,error in
            
            if let error = error {
                Logger.vpnProcess.error("Post Request Error: \(error.localizedDescription)")
              return
            }
            
            // ensure there is valid response code returned from this HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                Logger.vpnProcess.error("Invalid Response received from the server")
              return
            }
            
            // ensure there is data returned
            if data == nil {
                Logger.vpnProcess.error("nil Data received from the server")
              return
            }
//#if DEBUG
//            request.debug()
//            httpResponse.debug()
//#endif
            let parser = FinalAuthRespParser(data: data!)
            var authResp: AuthCompleteResp?
            if parser.parse() {
                authResp = parser.authResp
                self.credentials!.finalauth = authResp
            } else {
                if let error = parser.parserError {
                    Logger.vpnProcess.error("\(error.localizedDescription)")
                } else {
                    Logger.vpnProcess.error("Failed with unknown reason")
                }
            }
            //Use GCD to invoke the completion handler on the main thread
            DispatchQueue.main.async() {
                self.postAuthCallback!(authResp)
            }
          }
          // perform the task
          task.resume()
    }
}

class AuthRespParser: XMLParser {
    // Public property to hold the result
    var authResp: AuthRequestResp = AuthRequestResp()
    private var inside_opaque : Bool = false
    private var element : XMLElement?
    
    private var textBuffer: String = ""
    override init(data: Data) {
        super.init(data: data)
        self.delegate = self
    }
}

extension AuthRespParser: XMLParserDelegate {
    
    // Called when opening tag (`<elementName>`) is found
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        
        switch elementName {
        case "opaque":
            textBuffer = ""
            inside_opaque = true
            for (key, value) in attributeDict {
                authResp.opaque.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
            }
        case "auth":
            textBuffer = ""
            authResp.auth_id = attributeDict["id"]
        case "title":
            textBuffer = ""
        case "error":
            textBuffer = ""
        case "message":
            textBuffer = ""
        case "sso-v2-login":
            textBuffer = ""
        case "sso-v2-login-final":
            textBuffer = ""
        case "sso-v2-token-cookie-name":
            textBuffer = ""
        default:
            if inside_opaque == true {
                textBuffer = ""
                element = XMLElement(name: elementName, stringValue:"")
                for (key, value) in attributeDict {
                    element!.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
                }
                authResp.opaque.addChild(element!)
            }
            break
        }
    }
    
    // Called when closing tag (`</elementName>`) is found
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "opaque":
            inside_opaque = false
        case "title":
            authResp.auth_title = textBuffer
        case "error":
            authResp.auth_error = textBuffer
        case "message":
            authResp.auth_message = textBuffer
        case "sso-v2-login":
            authResp.login_url = textBuffer
        case "sso-v2-login-final":
            authResp.login_final_url = textBuffer
        case "sso-v2-token-cookie-name":
            authResp.token_cookie_name = textBuffer
        default:
            if inside_opaque == true {
                element?.stringValue = textBuffer
            }
            //Logger.vpnProcess.debug("Ignoring \(elementName)")
            break
        }
    }
    
    // Called when a character sequence is found
    // This may be called multiple times in a single element
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }
    
    // Called when a CDATA block is found
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            Logger.vpnProcess.debug("CDATA contains non-textual data, ignored")
            return
        }
        textBuffer += string
    }
    
    // For debugging
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        Logger.vpnProcess.error("\(parseError.localizedDescription)")
        Logger.vpnProcess.debug("on: \(parser.lineNumber) at: \(parser.columnNumber)")
    }
}

class FinalAuthRespParser: XMLParser {
    // Public property to hold the result
    var authResp: AuthCompleteResp = AuthCompleteResp()
    
    private var textBuffer: String = ""
    override init(data: Data) {
        super.init(data: data)
        self.delegate = self
    }
}

extension FinalAuthRespParser: XMLParserDelegate {
    
    // Called when opening tag (`<elementName>`) is found
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        
        switch elementName {
        case "auth":
            textBuffer = ""
            authResp.auth_id = attributeDict["id"]
        case "message":
            textBuffer = ""
        case "session-token":
            textBuffer = ""
        case "server-cert-hash":
            textBuffer = ""
        default:
            break
        }
    }
    
    // Called when closing tag (`</elementName>`) is found
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "message":
            authResp.auth_message = textBuffer
        case "session-token":
            authResp.session_token = textBuffer
        case "server-cert-hash":
            authResp.server_cert_hash = textBuffer
        default:
            //Logger.vpnProcess.debug("Ignoring \(elementName)")
            break
        }
    }
    
    // Called when a character sequence is found
    // This may be called multiple times in a single element
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }
    
    // Called when a CDATA block is found
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            Logger.vpnProcess.debug("CDATA contains non-textual data, ignored")
            return
        }
        textBuffer += string
    }
    
    // For debugging
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        Logger.vpnProcess.error("\(parseError.localizedDescription)")
        Logger.vpnProcess.debug("on: \(parser.lineNumber) at: \(parser.columnNumber)")
    }
}
