//
//  LoginViewModel.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import SwiftUI

// MARK: - Login State
enum LoginState: Equatable {
    case idle
    case loading
    case success
    case error(String)
    
    static func == (lhs: LoginState, rhs: LoginState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading, .loading):
            return true
        case (.success, .success):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Login View Model
@MainActor
class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var state: LoginState = .idle
    @Published var showPassword: Bool = false
    
    private var authManager: AuthManager
    private let deviceService: DeviceServiceProtocol
    private let keychainService = KeychainService()
    
    init(authManager: AuthManager,
         deviceService: DeviceServiceProtocol = DeviceService()) {
        self.authManager = authManager
        self.deviceService = deviceService
        loadSavedCredentials()
    }
    
    // MARK: - Validation
    var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    var isPasswordValid: Bool {
        return password.count >= 6
    }
    
    var isFormValid: Bool {
        return isEmailValid && isPasswordValid
    }
    
    // MARK: - Login Action
    func login() async {
        guard isFormValid else {
            state = .error("Please enter valid email and password (minimum 6 characters)")
            return
        }
        
        state = .loading
        
        // Ensure VoIP token is ready before proceeding with login
        let token = await deviceService.getTokenCodeWithRetry()
        if token.isEmpty {
            state = .error("Unable to generate VoIP push token. Please check your internet connection and try again.")
            return
        }
        
        do {
            _ = try await authManager.login(email: email, password: password)
            
            // Since the API response doesn't have a success field, we assume success if we get a response
            state = .success
            
            // Save credentials to keychain for future use
            saveCredentials()
            
            // Register device after successful login
            await registerDevice()
            
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    // MARK: - Device Registration
    private func registerDevice() async {
        // Get VoIP token with retry mechanism
        let voipToken = await deviceService.getTokenCodeWithRetry()
        
        // Check if device is already registered by looking at the current user's devices
        if let currentUser = authManager.currentUser,
           let devices = currentUser.devices,
           let currentDevice = devices.first(where: { device in
               device.platform == "ios" && 
               device.tokenCode == voipToken
           }) {
            
            if currentDevice.isRegistered {
                print("✅ Device already registered, skipping registration")
                return
            }
        }
        
        // Retry mechanism for device registration
        for attempt in 1...3 {
            do {
                let deviceInfo = DeviceInfo(
                    phone: deviceService.getDeviceInfo().phone,
                    tokenCode: voipToken,
                    platform: deviceService.getDeviceInfo().platform,
                    osVersion: deviceService.getDeviceInfo().osVersion,
                    manufacturer: deviceService.getDeviceInfo().manufacturer,
                    brand: deviceService.getDeviceInfo().brand
                )
                print("🔍 Device registration attempt \(attempt) - Token: \(deviceInfo.tokenCode)")
                
                let request = DeviceRegistrationRequest(
                    phone: deviceInfo.phone,
                    tokenCode: deviceInfo.tokenCode,
                    platform: deviceInfo.platform,
                    osVersion: deviceInfo.osVersion,
                    isRegistered: false, // Set to false since we're registering a new device
                    manufacturer: deviceInfo.manufacturer,
                    brand: deviceInfo.brand
                )
                
                // Use the authService from AuthManager for device registration
                let authService = AuthService()
                _ = try await authService.registerDevice(request: request)
                
                // Since success is optional, we'll just log the response
                print("✅ Device registration response received")
                return // Success, exit the retry loop
                
            } catch {
                print("❌ Device registration attempt \(attempt) failed: \(error.localizedDescription)")
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .unauthorized:
                        print("🔐 Authentication failed - token may be invalid")
                    case .forbidden:
                        print("🚫 Access forbidden - user doesn't have permission")
                    case .validationError(let message):
                        print("❌ Validation error: \(message)")
                    case .decodingError:
                        print("📄 Server returned invalid JSON response")
                    case .serverError(let message):
                        print("🌐 Server error: \(message)")
                    default:
                        print("🌐 Network error: \(networkError.localizedDescription)")
                    }
                }
                
                // If this is not the last attempt, wait before retrying
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay between retries
                }
            }
        }
        
        print("❌ Device registration failed after 3 attempts")
    }
    
    // MARK: - Reset State
    func resetState() {
        state = .idle
    }
    
    // MARK: - Update Auth Manager
    func updateAuthManager(_ authManager: AuthManager) {
        self.authManager = authManager
    }
    
    // MARK: - Clear Form
    func clearForm() {
        email = ""
        password = ""
        showPassword = false
        state = .idle
    }
    
    // MARK: - Clear Saved Credentials
    func clearSavedCredentials() {
        keychainService.delete(key: "saved_email")
        keychainService.delete(key: "saved_password")
        email = ""
        password = ""
    }
    
    // MARK: - Password Management
    private func loadSavedCredentials() {
        if let savedEmail = keychainService.retrieve(key: "saved_email", type: String.self) {
            email = savedEmail
        }
        if let savedPassword = keychainService.retrieve(key: "saved_password", type: String.self) {
            password = savedPassword
        }
    }
    
    private func saveCredentials() {
        try? keychainService.save(key: "saved_email", value: email)
        try? keychainService.save(key: "saved_password", value: password)
    }
    
} 