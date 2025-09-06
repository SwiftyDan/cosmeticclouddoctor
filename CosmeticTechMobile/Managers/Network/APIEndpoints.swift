//
//  APIEndpoints.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import Foundation

// MARK: - API Environment Configuration
enum APIEnvironment {
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
struct APIEndpoints {
    private let environment: APIEnvironment
    
    init(environment: APIEnvironment = .development) {
        self.environment = environment
    }
    
    // MARK: - Authentication Endpoints
    var login: String { "\(environment.baseURL)/login" }
    var logout: String { "\(environment.baseURL)/logout" }
    
    // MARK: - Device Management Endpoints
    var registerDevice: String { "\(environment.baseURL)/user-device" }
    
    // MARK: - User Management Endpoints
    var userProfile: String { "\(environment.baseURL)/user/profile" }
    var updateProfile: String { "\(environment.baseURL)/user/profile" }

    // MARK: - User Deletion Endpoint
    var deleteUser: String { "\(environment.baseURL)/user" }
    
    // MARK: - Call Management Endpoints
    var callHistory: String { "\(environment.baseURL)/call-history" }
    var createCall: String { "\(environment.baseURL)/calls/create" }
    var endCall: String { "\(environment.baseURL)/calls/end" }
    var callAction: String { "\(environment.baseURL)/call-action" }
    
    // MARK: - VoIP Endpoints
    var voipToken: String { "\(environment.baseURL)/voip/token" }
    var voipRegister: String { "\(environment.baseURL)/voip/register" }
    
    // MARK: - Consultation Endpoints
    func doctorConsultationVideo(clinicSlug: String, scriptId: Int) -> String {
        let base = "\(environment.baseURL)/doctor-consultation-video"
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            URLQueryItem(name: "clinic_slug", value: clinicSlug),
            URLQueryItem(name: "script_id", value: String(scriptId))
        ]
        return comps?.url?.absoluteString ?? base
    }
    
    func updateDoctorConsultationVideoStatus(scriptId: Int, clinicSlug: String, status: Int) -> String {
        let base = "\(environment.baseURL)/doctor-consultation-video/\(scriptId)"
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
         let base = "\(environment.baseURL)/queue-entries"
         var comps = URLComponents(string: base)
         comps?.queryItems = [
             URLQueryItem(name: "doctor_user_uuid", value: doctorUserUUID),
             URLQueryItem(name: "doctor_user_id", value: String(doctorUserId))
         ]
         return comps?.url?.absoluteString ?? base
     }
    
    /// Builds the queue-remove URL for removing items from queue
    func queueRemoveURL() -> String {
        return "\(environment.baseURL)/queue-remove"
    }
    
    // MARK: - Utility
    var environmentName: String { environment.name }
    var baseURL: String { environment.baseURL }
}

// MARK: - Global API Configuration
class APIConfiguration {
    static let shared = APIConfiguration()
    
    private init() {}
    
    // Default environment - can be changed at runtime
    #if DEBUG
    var currentEnvironment: APIEnvironment = .production
    #else
    var currentEnvironment: APIEnvironment = .production
    #endif
    
    // Get endpoints for current environment
    var endpoints: APIEndpoints {
        return APIEndpoints(environment: currentEnvironment)
    }
    
    // Change environment at runtime
    func setEnvironment(_ environment: APIEnvironment) {
        currentEnvironment = environment
        print("🌐 API Environment changed to: \(environment.name)")
        print("🔗 Base URL: \(environment.baseURL)")
    }
    
    // Get current environment info
    func getCurrentEnvironmentInfo() -> String {
        return "Environment: \(currentEnvironment.name) - URL: \(currentEnvironment.baseURL)"
    }
}
