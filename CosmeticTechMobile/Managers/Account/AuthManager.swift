//
//  AuthManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import SwiftUI

// MARK: - Auth Manager
@MainActor
class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var isLoggingOut: Bool = false
    
    private let authService: AuthServiceProtocol
    
    init(authService: AuthServiceProtocol = AuthService()) {
        self.authService = authService
        checkLoginStatus()
    }
    
    // MARK: - Login Status Check
    private func checkLoginStatus() {
        isLoggedIn = authService.isLoggedIn()
        currentUser = authService.getCurrentUser()
    }
    
    // MARK: - Login
    func login(email: String, password: String) async throws -> LoginResponse {
        let response = try await authService.login(email: email, password: password)
        
        // Since the API response doesn't have a success field, we assume success if we get a response
        isLoggedIn = true
        currentUser = response.user
        
        return response
    }
    
    // MARK: - Logout
    func logout() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        do {
            try await authService.logout()
        } catch {
            // Even if API logout fails, we still want to logout locally
            authService.logoutLocal()
        }
        
        // Clear saved credentials from keychain
        let keychain = KeychainService()
        keychain.delete(key: "saved_email")
        keychain.delete(key: "saved_password")
        
        isLoggedIn = false
        currentUser = nil
        isLoggingOut = false
    }

    // MARK: - Deactivate Account
    func deactivateAccount() async {
        do {
            try await authService.deactivateAccount()
        } catch {
            // Ignore server-side errors; we still want to redirect to login
        }
        isLoggedIn = false
        currentUser = nil
    }
    
    // MARK: - Get Auth Token
    func getAuthToken() -> String? {
        return authService.getAuthToken()
    }
    
    // MARK: - User Validation
    /// Validates that the user has complete and valid information
    /// This is required before allowing calls to be received
    func validateUserForCalls() -> Bool {
        guard isLoggedIn else {
            print("🚫 Call validation failed: User not logged in")
            return false
        }
        
        guard let user = currentUser else {
            print("🚫 Call validation failed: No user data available")
            return false
        }
        
        // Check if user has required fields
        guard let name = user.name, !name.isEmpty else {
            print("🚫 Call validation failed: User name is empty or nil")
            return false
        }
        
        guard !user.email.isEmpty else {
            print("🚫 Call validation failed: User email is empty")
            return false
        }
        
        guard user.userId > 0 else {
            print("🚫 Call validation failed: Invalid user ID")
            return false
        }
        
        // Check if user has authentication token
        guard let authToken = getAuthToken(), !authToken.isEmpty else {
            print("🚫 Call validation failed: No authentication token")
            return false
        }
        
        print("✅ Call validation passed for user: \(name) (ID: \(user.userId))")
        return true
    }
    
    /// Gets current user info for debugging
    func getCurrentUserInfo() -> String {
        guard let user = currentUser else {
            return "No user data"
        }
        
        return "User: \(user.name), Email: \(user.email), ID: \(user.userId ?? 0), Logged in: \(isLoggedIn)"
    }
} 