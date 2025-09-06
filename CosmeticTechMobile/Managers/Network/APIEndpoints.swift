//
//  APIEndpoints.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import Foundation

// MARK: - API Environment Configuration (Legacy - kept for backward compatibility)
enum LegacyAPIEnvironment {
    case development
    case staging
    case production
    
    var baseURL: String {
        switch self {
        case .development:
            return "https://testing.cosmeticcloud.tech/api"
        case .staging:
            return "https://staging.cosmeticcloud.tech/api"
        case .production:
            return "https://cosmeticcloud.tech/api"
        }
    }
    
    var name: String {
        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}

// MARK: - API Endpoints
class APIEndpoints: ObservableObject {
    private let environmentManager = EnvironmentManager.shared
    
    init() {
        // Use EnvironmentManager for dynamic environment switching
        // Listen for environment changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(environmentChanged),
            name: .environmentChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func environmentChanged() {
        // Trigger UI update when environment changes
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Authentication Endpoints
    var login: String { "\(environmentManager.currentAPIURL)/login" }
    var logout: String { "\(environmentManager.currentAPIURL)/logout" }
    
    // MARK: - Device Management Endpoints
    var registerDevice: String { "\(environmentManager.currentAPIURL)/user-device" }
    
    // MARK: - User Management Endpoints
    var userProfile: String { "\(environmentManager.currentAPIURL)/user/profile" }
    var updateProfile: String { "\(environmentManager.currentAPIURL)/user/profile" }

    // MARK: - User Deletion Endpoint
    var deleteUser: String { "\(environmentManager.currentAPIURL)/user" }
    
    // MARK: - Call Management Endpoints
    var callHistory: String { "\(environmentManager.currentAPIURL)/call-history" }
    var createCall: String { "\(environmentManager.currentAPIURL)/calls/create" }
    var endCall: String { "\(environmentManager.currentAPIURL)/calls/end" }
    var callAction: String { "\(environmentManager.currentAPIURL)/call-action" }
    
    // MARK: - VoIP Endpoints
    var voipToken: String { "\(environmentManager.currentAPIURL)/voip/token" }
    var voipRegister: String { "\(environmentManager.currentAPIURL)/voip/register" }
    
    // MARK: - Consultation Endpoints
    func doctorConsultationVideo(clinicSlug: String, scriptId: Int) -> String {
        let base = "\(environmentManager.currentAPIURL)/doctor-consultation-video"
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            URLQueryItem(name: "clinic_slug", value: clinicSlug),
            URLQueryItem(name: "script_id", value: String(scriptId))
        ]
        return comps?.url?.absoluteString ?? base
    }
    
    func updateDoctorConsultationVideoStatus(scriptId: Int, clinicSlug: String, status: Int) -> String {
        let base = "\(environmentManager.currentAPIURL)/doctor-consultation-video/\(scriptId)"
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            URLQueryItem(name: "clinic_slug", value: clinicSlug),
            URLQueryItem(name: "status", value: String(status))
        ]
        return comps?.url?.absoluteString ?? base
    }

     // MARK: - Queue Endpoints
     /// Builds the queue entries URL with required doctor identifiers
     func queueEntriesURL(doctorUserUUID: String, doctorUserId: Int) -> String {
         let base = "\(environmentManager.currentAPIURL)/queue-entries"
         var comps = URLComponents(string: base)
         comps?.queryItems = [
             URLQueryItem(name: "doctor_user_uuid", value: doctorUserUUID),
             URLQueryItem(name: "doctor_user_id", value: String(doctorUserId))
         ]
         return comps?.url?.absoluteString ?? base
     }
    
    /// Builds the queue-remove URL for removing items from queue
    func queueRemoveURL() -> String {
        return "\(environmentManager.currentAPIURL)/queue-remove"
    }
    
    // MARK: - Utility
    var environmentName: String { environmentManager.currentEnvironment.displayName }
    var baseURL: String { environmentManager.currentAPIURL }
}

// MARK: - Global API Configuration (Updated to use EnvironmentManager)
class APIConfiguration {
    static let shared = APIConfiguration()
    private let environmentManager = EnvironmentManager.shared
    private let _endpoints: APIEndpoints
    
    private init() {
        _endpoints = APIEndpoints()
    }
    
    // Get endpoints for current environment
    var endpoints: APIEndpoints {
        return _endpoints
    }
    
    // Change environment at runtime
    func setEnvironment(_ environment: APIEnvironment) {
        environmentManager.setEnvironment(environment)
    }
    
    // Force refresh endpoints (useful for debugging)
    func refreshEndpoints() {
        _endpoints.objectWillChange.send()
    }
    
    // Get current environment info
    func getCurrentEnvironmentInfo() -> String {
        return environmentManager.getEnvironmentInfo()
    }
    
    // Legacy support for backward compatibility
    var currentEnvironment: LegacyAPIEnvironment {
        switch environmentManager.currentEnvironment {
        case .production: return .production
        case .staging: return .staging
        case .development: return .development
        case .custom: return .development // Custom maps to development for legacy support
        }
    }
}
