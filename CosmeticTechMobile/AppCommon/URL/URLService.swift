//
//  URLService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import UIKit

// MARK: - URL Service Protocol (Interface Segregation Principle)
protocol URLServiceProtocol {
    func openURL(_ urlString: String, completion: @escaping (Bool) -> Void)
    func canOpenURL(_ urlString: String) -> Bool
    func validateURL(_ urlString: String) -> Bool
}

// MARK: - URL Service Implementation (Single Responsibility Principle)
class URLService: URLServiceProtocol {
    
    // MARK: - URL Opening
    func openURL(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard validateURL(urlString) else {
            print("❌ Invalid URL format: \(urlString)")
            completion(false)
            return
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ Failed to create URL from string: \(urlString)")
            completion(false)
            return
        }
        
        // Try multiple opening strategies
        openURLWithMultipleStrategies(url, completion: completion)
    }
    
    // MARK: - URL Validation
    func canOpenURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    // MARK: - Private Methods
    private func openURLWithMultipleStrategies(_ url: URL, completion: @escaping (Bool) -> Void) {
        print("🌐 Attempting to open URL: \(url.absoluteString)")
        
        // Strategy 1: Try opening in Safari with options
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = [
            .universalLinksOnly: false
        ]
        
        UIApplication.shared.open(url, options: options) { success in
            if success {
                print("✅ Successfully opened URL in Safari: \(url.absoluteString)")
                completion(true)
            } else {
                print("⚠️ Failed to open URL in Safari, trying alternative method...")
                self.tryAlternativeOpeningMethod(url, completion: completion)
            }
        }
    }
    
    private func tryAlternativeOpeningMethod(_ url: URL, completion: @escaping (Bool) -> Void) {
        // Strategy 2: Try opening with different options
        let alternativeOptions: [UIApplication.OpenExternalURLOptionsKey: Any] = [
            .universalLinksOnly: false
        ]
        
        UIApplication.shared.open(url, options: alternativeOptions) { success in
            if success {
                print("✅ Successfully opened URL with alternative method: \(url.absoluteString)")
                completion(true)
            } else {
                print("❌ All URL opening methods failed for: \(url.absoluteString)")
                completion(false)
            }
        }
    }
}

// MARK: - URL Service Factory (Dependency Inversion Principle)
class URLServiceFactory {
    static func createURLService() -> URLServiceProtocol {
        return URLService()
    }
} 