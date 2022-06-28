//
//  AuthManager.swift
//  saml-vpn-manager
//
//  Created by Shankar Giri Venkita Giri on 25/06/22.
//

import Foundation

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
        var request = URLRequest(url: URL(string: self.credentials!.portal)!)
        request.setValue("AnyConnect Linux_64 4.7.00136", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("1", forHTTPHeaderField: "X-Transcend-Version")
        request.setValue("1", forHTTPHeaderField: "X-Aggregate-Auth")
        request.setValue("true", forHTTPHeaderField: "X-Support-HTTP-Auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
//        let base = XMLElement(name: "xml")
//        let httpbody = XMLDocument(rootElement: base)
        let config_auth =  XMLElement(name: "config-auth", stringValue:"")
        let httpbody = XMLDocument(rootElement: config_auth)
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
        let httpBody = "<?xml version=\'1.0\' encoding=\'UTF-8\'?>" + httpbody.xmlString
        request.httpBody = httpBody.data(using: .utf8)
        return request
    }
    
    private func createFinalAuthRequest(authReqResp: AuthRequestResp?) -> URLRequest {
        var request = URLRequest(url: URL(string: self.credentials!.portal)!)
        request.setValue("AnyConnect Linux_64 4.7.00136", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("1", forHTTPHeaderField: "X-Transcend-Version")
        request.setValue("1", forHTTPHeaderField: "X-Aggregate-Auth")
        request.setValue("true", forHTTPHeaderField: "X-Support-HTTP-Auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
//        let base = XMLElement(name: "xml")
//        let httpbody = XMLDocument(rootElement: base)
        let config_auth =  XMLElement(name: "config-auth", stringValue:"")
        let httpbody = XMLDocument(rootElement: config_auth)
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
        let httpBody = "<?xml version=\'1.0\' encoding=\'UTF-8\'?>" + httpbody.xmlString
        print(httpBody)
        request.httpBody = httpBody.data(using: .utf8)
        return request
    }
    
    func sendPreAuthRequest(request: URLRequest) -> Void {
        let session = URLSession(configuration:URLSessionConfiguration.default)
        
        let task = URLSession.shared.dataTask(with: request) {
            data,response,error in
            
            if let error = error {
              print("Post Request Error: \(error.localizedDescription)")
              return
            }
            
            // ensure there is valid response code returned from this HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
              print("Invalid Response received from the server")
              return
            }
            
            // ensure there is data returned
            if data == nil {
              print("nil Data received from the server")
              return
            }
            print(String(decoding: data!, as: UTF8.self))
            let parser = AuthRespParser(data: data!)
            var authResp: AuthRequestResp?
            if parser.parse() {
                authResp = parser.authResp
                self.credentials!.preauth = authResp
            } else {
                if let error = parser.parserError {
                    print(error)
                } else {
                    print("Failed with unknown reason")
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
        let session = URLSession(configuration:URLSessionConfiguration.default)
        
        let task = URLSession.shared.dataTask(with: request) {
            data,response,error in
            
            if let error = error {
              print("Post Request Error: \(error.localizedDescription)")
              return
            }
            
            // ensure there is valid response code returned from this HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
              print("Invalid Response received from the server")
              return
            }
            
            // ensure there is data returned
            if data == nil {
              print("nil Data received from the server")
              return
            }
            print(String(decoding: data!, as: UTF8.self))
            let parser = FinalAuthRespParser(data: data!)
            var authResp: AuthCompleteResp?
            if parser.parse() {
                authResp = parser.authResp
                self.credentials!.finalauth = authResp
            } else {
                if let error = parser.parserError {
                    print(error)
                } else {
                    print("Failed with unknown reason")
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
            //print("Ignoring \(elementName)")
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
            print("CDATA contains non-textual data, ignored")
            return
        }
        textBuffer += string
    }
    
    // For debugging
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print(parseError)
        print("on:", parser.lineNumber, "at:", parser.columnNumber)
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
            //print("Ignoring \(elementName)")
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
            print("CDATA contains non-textual data, ignored")
            return
        }
        textBuffer += string
    }
    
    // For debugging
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print(parseError)
        print("on:", parser.lineNumber, "at:", parser.columnNumber)
    }
}
