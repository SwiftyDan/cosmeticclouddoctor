//
//  AuthService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation

// MARK: - Auth Service Protocol
protocol AuthServiceProtocol {
    func login(email: String, password: String) async throws -> LoginResponse
    func registerDevice(request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse
    func logout() async throws
    func logoutLocal()
    func isLoggedIn() -> Bool
    func getCurrentUser() -> User?
    func getAuthToken() -> String?
    func deactivateAccount() async throws
}

// MARK: - Auth Service Implementation
class AuthService: AuthServiceProtocol {
    private let authenticationAPIService: AuthenticationAPIService
    private let deviceAPIService: DeviceAPIService
    private let keychainService: KeychainServiceProtocol
    private let userAPIService: UserAPIService
    
    init(authenticationAPIService: AuthenticationAPIService = AuthenticationAPIService(),
         deviceAPIService: DeviceAPIService = DeviceAPIService(),
         keychainService: KeychainServiceProtocol = KeychainService(),
         userAPIService: UserAPIService = UserAPIService()) {
        self.authenticationAPIService = authenticationAPIService
        self.deviceAPIService = deviceAPIService
        self.keychainService = keychainService
        self.userAPIService = userAPIService
    }
    
    func login(email: String, password: String) async throws -> LoginResponse {
        // Retry mechanism for login requests (especially important for older devices)
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                let response = try await authenticationAPIService.login(email: email, password: password)
                return response
                
            } catch {
                lastError = error
                
                // If this is not the last attempt, wait before retrying
                if attempt < 3 {
                    let delay = Double(attempt) * 2.0 // Progressive delay: 2s, 4s
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All attempts failed
        throw lastError ?? NetworkError.serverError("Login failed after 3 attempts")
    }
    
    func registerDevice(request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        return try await deviceAPIService.registerDevice(request: request)
    }
    
    func logout() async throws {
        try await authenticationAPIService.logout()
    }
    
    func logoutLocal() {
        keychainService.delete(key: "auth_token")
        keychainService.delete(key: "user_data")

    }
    
    func isLoggedIn() -> Bool {
        return getAuthToken() != nil
    }
    
    func getCurrentUser() -> User? {
        return keychainService.retrieve(key: "user_data", type: User.self)
    }
    
    func getUserUUID() -> String? {
        return keychainService.retrieve(key: "user_uuid", type: String.self)
    }
    
    func getAuthToken() -> String? {
        return keychainService.retrieve(key: "auth_token", type: String.self)
    }

    // MARK: - Deactivate Account
    func deactivateAccount() async throws {
        // Attempt server-side deactivation; regardless of outcome, perform local cleanup
        do {
            _ = try await userAPIService.deactivateAccount()
        } catch {
            // Ignore server errors for deactivation to ensure local cleanup
        }
        logoutLocal()
    }
} 