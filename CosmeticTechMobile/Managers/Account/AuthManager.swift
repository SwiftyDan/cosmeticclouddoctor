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
        
        print("🔐 Starting comprehensive logout cleanup...")
        
        do {
            try await authService.logout()
        } catch {
            // Even if API logout fails, we still want to logout locally
            authService.logoutLocal()
        }
        
        // Clear all local data and cache
        await clearAllLocalData()
        
        isLoggedIn = false
        currentUser = nil
        isLoggingOut = false
        
        print("✅ Logout completed - all data cleared")
    }
    
    // MARK: - Clear All Local Data
    private func clearAllLocalData() async {
        print("🧹 Clearing all local data and cache...")
        
        // 1. Clear Keychain data
        let keychain = KeychainService()
        keychain.delete(key: "auth_token")
        keychain.delete(key: "user_data")
        keychain.delete(key: "user_uuid")
        keychain.delete(key: "saved_email")
        keychain.delete(key: "saved_password")
        print("✅ Keychain data cleared")
        
        // 2. Clear UserDefaults data
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "deviceToken")
        userDefaults.removeObject(forKey: "app_badge_count")
        userDefaults.removeObject(forKey: "API_ENVIRONMENT")
        userDefaults.removeObject(forKey: "redirect_url")
        userDefaults.removeObject(forKey: "pusher_key")
        userDefaults.synchronize()
        print("✅ UserDefaults data cleared")
        
        // 3. Queue data will be cleared when HomeViewModel is recreated
        print("✅ Queue data will be cleared on next app launch")
        
        // 4. Clear call history data
        CallKitManager.shared.clearCallData()
        print("✅ Call data cleared")
        
        // 5. Clear Jitsi meeting state
        GlobalJitsiManager.shared.clearJitsiState()
        print("✅ Jitsi state cleared")
        
        // 6. Reset badge count
        BadgeManager.shared.resetBadge()
        print("✅ Badge count reset")
        
        // 7. Clear VoIP push handler state
        VoIPPushHandler.shared.clearVoIPState()
        print("✅ VoIP state cleared")
        
        print("🧹 All local data and cache cleared successfully")
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
        
        return "User: \(user.name), Email: \(user.email), ID: \(user.userId), Logged in: \(isLoggedIn)"
    }
} 