//
//  AuthenticationHandler.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 9/4/25.
//

import Foundation
import SwiftUI
import os.log

// MARK: - Authentication Handler
@MainActor
class AuthenticationHandler: ObservableObject {
    static let shared = AuthenticationHandler()
    
    private let logger = Logger(subsystem: "com.cosmetictech.auth", category: "AuthenticationHandler")
    private var authManager: AuthManager?
    
    private init() {
        // Set up notification observers
        setupNotificationObservers()
    }
    
    // MARK: - Setup
    func setAuthManager(_ authManager: AuthManager) {
        self.authManager = authManager
        logger.info("🔐 AuthenticationHandler initialized with AuthManager")
    }
    
    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUnauthorizedResponse),
            name: NSNotification.Name("UnauthorizedResponse"),
            object: nil
        )
    }
    
    // MARK: - Handle Unauthorized Response
    @objc private func handleUnauthorizedResponse() {
        logger.warning("🚨 Unauthorized response detected, logging out user")
        logger.warning("🔍 Current auth state - isLoggedIn: \(self.authManager?.isLoggedIn ?? false)")
        
        Task {
            await performLogout()
        }
    }
    
    // MARK: - Perform Logout
    private func performLogout() async {
        guard let authManager = authManager else {
            logger.error("❌ AuthManager not available for logout")
            return
        }
        
        logger.info("🔐 Performing automatic logout due to unauthorized response")
        logger.info("🔍 Auth state before logout - isLoggedIn: \(authManager.isLoggedIn)")
        
        // Perform logout through AuthManager
        await authManager.logout()
        
        // Verify logout was successful
        logger.info("🔍 Auth state after logout - isLoggedIn: \(authManager.isLoggedIn)")
        
        // Post notification that logout is complete
        NotificationCenter.default.post(name: NSNotification.Name("UserLoggedOut"), object: nil)
        
        logger.info("✅ Automatic logout completed")
    }
    
    // MARK: - Check Authentication Status
    func checkAuthenticationStatus() -> Bool {
        return authManager?.isLoggedIn ?? false
    }
    
    // MARK: - Manual Logout Trigger
    func triggerLogout() {
        logger.info("🔐 Manual logout triggered")
        handleUnauthorizedResponse()
    }
}

// MARK: - Network Error Extension
extension NetworkError {
    /// Check if this error should trigger an automatic logout
    var shouldTriggerLogout: Bool {
        switch self {
        case .unauthorized:
            return true
        case .forbidden:
            return true
        default:
            return false
        }
    }
}

// MARK: - Notification Names
extension NSNotification.Name {
    static let unauthorizedResponse = NSNotification.Name("UnauthorizedResponse")
    static let userLoggedOut = NSNotification.Name("UserLoggedOut")
}
