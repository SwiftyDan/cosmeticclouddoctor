//
//  WebViewService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import SwiftUI

class WebViewService: ObservableObject {
    static let shared = WebViewService()
    
    @Published var showWebView = false
    @Published var webViewURL: URL?
    
    private init() {}
    
    func presentWebView(url: String) {
        guard let url = URL(string: url) else {
            // Invalid URL - could log to analytics or crash reporting
            return
        }
        
        DispatchQueue.main.async {
            self.webViewURL = url
            self.showWebView = true
        }
    }
    
    func dismissWebView() {
        DispatchQueue.main.async {
            self.showWebView = false
            self.webViewURL = nil
        }
    }
    
    func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
} 