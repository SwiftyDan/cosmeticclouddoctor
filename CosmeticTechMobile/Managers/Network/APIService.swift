//
//  APIService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import Foundation
import os.log

// MARK: - Response Models
struct SimpleResponse: Codable {
    let success: Bool
    
    enum CodingKeys: String, CodingKey {
        case success
    }
}

// MARK: - Call Action Types
enum CallAction: String, Codable {
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
}

// MARK: - API Service Protocol
protocol APIServiceProtocol {
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]?,
        authToken: String?,
        configuration: RequestConfiguration?,
        responseType: T.Type
    ) async throws -> T
    
    func cancelAllRequests()
}

// MARK: - API Service Implementation
class APIService: APIServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let apiConfiguration: APIConfiguration
    private let logger = Logger(subsystem: "com.cosmetictech.api", category: "APIService")
    
    init(networkService: NetworkServiceProtocol = NetworkService(baseURL: APIConfiguration.shared.endpoints.baseURL), 
         apiConfiguration: APIConfiguration = APIConfiguration.shared) {
        self.networkService = networkService
        self.apiConfiguration = apiConfiguration
    }
    
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]?,
        authToken: String?,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        
        let config = configuration ?? .default
        
        // Log the API request
        logger.info("🚀 API Request: \(method.rawValue) \(endpoint)")
        
        // Build request with authentication if token provided
        let request: URLRequest
        if let authToken = authToken {
            request = APIRequestBuilder.buildAuthenticatedRequest(
                url: URL(string: endpoint)!,
                method: method,
                authToken: authToken,
                body: body
            )
        } else {
            request = APIRequestBuilder.buildRequest(
                url: URL(string: endpoint)!,
                method: method,
                body: body
            )
        }
        
        // Use the network service to make the request
        return try await networkService.request(
            request: request,
            configuration: config,
            responseType: responseType
        )
    }
    
    func cancelAllRequests() {
        if let networkService = networkService as? NetworkService {
            networkService.cancelAllRequests()
        }
        logger.info("🛑 All API requests cancelled")
    }
}

// MARK: - Authentication API Service
class AuthenticationAPIService {
    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.cosmetictech.auth", category: "AuthenticationAPIService")
    
    init(apiService: APIServiceProtocol = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }
    
    func login(email: String, password: String) async throws -> LoginResponse {
        // Use current environment settings
        let endpoints = APIConfiguration.shared.endpoints
        let body = RequestBodyBuilder.loginBody(email: email, password: password)
        
        logger.info("🔐 Attempting login for user: \(email)")
        
        // Use aggressive configuration for login to ensure responsiveness
        let response: LoginResponse = try await apiService.request(
            endpoint: endpoints.login,
            method: .POST,
            body: body,
            authToken: nil,
            configuration: .aggressive,
            responseType: LoginResponse.self
        )
        
        // Save user data and token on successful login
        try keychainService.save(key: "auth_token", value: response.token)
        try keychainService.save(key: "user_data", value: response.user)
        if let uuid = response.user.userUUID, !uuid.isEmpty {
            try? keychainService.save(key: "user_uuid", value: uuid)
        }
        logger.info("✅ Login successful for user: \(response.user.email)")
        
        return response
    }
    
    func logout() async throws {
        guard let authToken = getAuthToken() else {
            // If no auth token exists, just perform local logout
            logoutLocal()
            return
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        let voipToken = VoIPPushHandler.shared.getCurrentVoIPToken() ?? ""
        let body = RequestBodyBuilder.logoutBody(tokenCode: voipToken)
        
        logger.info("🔐 Logging out user with VoIP token: \(voipToken.isEmpty ? "VOIP_TOKEN_PLACEHOLDER" : voipToken)")
        
        do {
            let _: EmptyResponse = try await apiService.request(
                endpoint: endpoints.logout,
                method: .POST,
                body: body,
                authToken: authToken,
                configuration: .default,
                responseType: EmptyResponse.self
            )
            
            logger.info("✅ Server logout successful")
        } catch {
            logger.warning("⚠️ Server logout failed: \(error.localizedDescription)")
            // Continue with local logout even if server logout fails
        }
        
        // Always perform local logout regardless of server response
        logoutLocal()
    }
    
    private func logoutLocal() {
        keychainService.delete(key: "auth_token")
        keychainService.delete(key: "user_data")
        logger.info("✅ Local logout successful")
    }
    
    private func getAuthToken() -> String? {
        return keychainService.retrieve(key: "auth_token", type: String.self)
    }
}

// MARK: - Device API Service
class DeviceAPIService {
    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.cosmetictech.device", category: "DeviceAPIService")
    
    init(apiService: APIServiceProtocol = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }
    
    func registerDevice(request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        guard let authToken = getAuthToken() else {
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        let body = RequestBodyBuilder.deviceRegistrationBody(
            phone: request.phone,
            tokenCode: request.tokenCode,
            platform: request.platform,
            osVersion: request.osVersion,
            isRegistered: request.isRegistered,
            manufacturer: request.manufacturer,
            brand: request.brand
        )
        
        logger.info("🔧 Registering device with token: \(request.tokenCode)")
        logger.debug("📱 Device info: \(body)")
        
        // Use conservative configuration for device registration
        let response: DeviceRegistrationResponse = try await apiService.request(
            endpoint: endpoints.registerDevice,
            method: .POST,
            body: body,
            authToken: authToken,
            configuration: .conservative,
            responseType: DeviceRegistrationResponse.self
        )
        
        logger.info("✅ Device registration response received")
        return response
    }
    
    private func getAuthToken() -> String? {
        return keychainService.retrieve(key: "auth_token", type: String.self)
    }
}

// MARK: - Call API Service
class CallAPIService {
    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.cosmetictech.call", category: "CallAPIService")
    
    init(apiService: APIServiceProtocol = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }
    
    func createCall(phoneNumber: String, callType: String, conferenceUrl: String? = nil) async throws -> EmptyResponse {
        guard let authToken = getAuthToken() else {
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        let body = RequestBodyBuilder.callCreationBody(
            phoneNumber: phoneNumber,
            callType: callType,
            conferenceUrl: conferenceUrl
        )
        
        logger.info("📞 Creating call for: \(phoneNumber), type: \(callType)")
        
        // Use aggressive configuration for call creation to ensure responsiveness
        let response: EmptyResponse = try await apiService.request(
            endpoint: endpoints.createCall,
            method: .POST,
            body: body,
            authToken: authToken,
            configuration: .aggressive,
            responseType: EmptyResponse.self
        )
        
        logger.info("✅ Call created successfully")
        return response
    }
    
    func getCallHistory() async throws -> [CallHistory] {
        guard let authToken = getAuthToken() else {
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        
        logger.info("📋 Fetching call history")
        
        // Use default configuration for call history
        let response: [CallHistory] = try await apiService.request(
            endpoint: endpoints.callHistory,
            method: .GET,
            body: nil,
            authToken: authToken,
            configuration: .default,
            responseType: [CallHistory].self
        )
        
        logger.info("✅ Call history fetched: \(response.count) calls")
        return response
    }
    
    // MARK: - Consultation Details
    struct ConsultationVideoResponse: Codable {
        struct Conference: Codable {
            let roomName: String
            let displayName: String
            enum CodingKeys: String, CodingKey { case roomName = "room_name"; case displayName = "display_name" }
        }
        struct QA: Codable { let label: String; let answer: String }
        struct DataPayload: Codable {
            let scriptNumber: String
            let patientName: String
            let dateOfBirth: String
            let doctorName: String
            let nurseName: String
            let consultationDate: String
            let medicalConsultation: [QA]
            let notes: String?
            let patientConsentPhotographs: String
            let patientConsentToTreatment: String
            let patientSignature: String?
            let nurseSignature: String?
            let scriptStatus: String
            let scriptProducts: String?
            enum CodingKeys: String, CodingKey {
                case scriptNumber = "script_number"
                case patientName = "patient_name"
                case dateOfBirth = "date_of_birth"
                case doctorName = "doctor_name"
                case nurseName = "nurse_name"
                case consultationDate = "consultation_date"
                case medicalConsultation = "medical_consultation"
                case notes
                case patientConsentPhotographs = "patient_consent_photographs"
                case patientConsentToTreatment = "patient_consent_to_treatment"
                case patientSignature = "patient_signature"
                case nurseSignature = "nurse_signature"
                case scriptStatus = "script_status"
                case scriptProducts = "script_products"
            }
        }
        let conference: Conference
        let data: DataPayload
    }

    func fetchConsultationVideo(clinicSlug: String, scriptId: Int) async throws -> ConsultationVideoResponse {
        guard let authToken = getAuthToken() else { throw NetworkError.unauthorized }
        let endpoints = APIConfiguration.shared.endpoints
        let url = endpoints.doctorConsultationVideo(clinicSlug: clinicSlug, scriptId: scriptId)
        return try await apiService.request(
            endpoint: url,
            method: .GET,
            body: nil,
            authToken: authToken,
            configuration: RequestConfiguration.default,
            responseType: ConsultationVideoResponse.self
        )
    }

    func updateConsultationStatus(scriptId: Int, clinicSlug: String, status: Int) async throws -> EmptyResponse {
        guard let authToken = getAuthToken() else { throw NetworkError.unauthorized }
        let endpoints = APIConfiguration.shared.endpoints
        let url = endpoints.updateDoctorConsultationVideoStatus(scriptId: scriptId, clinicSlug: clinicSlug, status: status)
        return try await apiService.request(
            endpoint: url,
            method: .PUT,
            body: nil,
            authToken: authToken,
            configuration: RequestConfiguration.default,
            responseType: EmptyResponse.self
        )
    }

    private func getAuthToken() -> String? {
        return keychainService.retrieve(key: "auth_token", type: String.self)
    }
}

// MARK: - Queue API Service
class QueueAPIService {
    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.cosmetictech.queue", category: "QueueAPIService")
    
    init(apiService: APIServiceProtocol = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }
    
    struct QueueResponse: Codable {
        let success: Bool?
        let data: [QueueEntry]
    }
    
    struct QueueEntry: Codable {
        let id: String?
        let uuid: String?
        let patientName: String?
        let callerName: String?
        let clinicName: String?
        let clinicSlug: String?
        let createdAt: String?
        let scriptId: Int?
        let scriptUUID: String?
        let scriptNumber: String?
        let roomName: String?
        let timeonly: String?
        let doctorUserId: Int?
        
        enum CodingKeys: String, CodingKey {
            case id
            case uuid
            case patientName = "patient_name"
            case callerName = "caller_name"
            case clinicName = "clinic_name"
            case clinicSlug = "clinic_slug"
            case createdAt = "created_at"
            case scriptId = "script_id"
            case scriptUUID = "script_uuid"
            case scriptNumber = "script_number"
            case roomName = "room_name"
            case timeonly
            case doctorUserId = "doctor_user_id"
        }
    }
    
    func fetchQueueEntries() async throws -> [QueueItem] {
        guard let user: User = keychainService.retrieve(key: "user_data", type: User.self) else {
            logger.error("❌ Failed to fetch queue entries: No user data found")
            throw NetworkError.unauthorized
        }
        guard let token = keychainService.retrieve(key: "auth_token", type: String.self) else {
            logger.error("❌ Failed to fetch queue entries: No auth token found")
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        let url = endpoints.queueEntriesURL(doctorUserUUID: user.userUUID ?? "", doctorUserId: user.doctorUserId ?? user.userId)
        
        logger.info("📋 Fetching queue entries:")
        logger.info("   - URL: \(url)")
        logger.info("   - Doctor User ID: \(user.doctorUserId ?? user.userId)")
        logger.info("   - Doctor User UUID: \(user.userUUID ?? "nil")")
        logger.info("   - Auth Token: \(token.prefix(10))...")
        
        // Use GET with auth
        let entries: [QueueEntry]
        do {
            logger.info("🔄 Attempting direct array response...")
            // Response may be raw array or wrapped in { success, data }
            entries = try await apiService.request(
                endpoint: url,
                method: .GET,
                body: nil,
                authToken: token,
                configuration: .default,
                responseType: [QueueEntry].self
            )
            logger.info("✅ Received direct array response with \(entries.count) entries")
        } catch {
            logger.info("🔄 Direct array failed, trying wrapped response...")
            // Try wrapped response
            let wrapped: QueueResponse = try await apiService.request(
                endpoint: url,
                method: .GET,
                body: nil,
                authToken: token,
                configuration: .default,
                responseType: QueueResponse.self
            )
            entries = wrapped.data
            logger.info("✅ Received wrapped response with \(entries.count) entries")
        }
        
        logger.info("📊 Raw API Response Details:")
        for (index, entry) in entries.enumerated() {
            logger.info("   Entry \(index + 1):")
            logger.info("     - ID: \(entry.id ?? "nil")")
            logger.info("     - UUID: \(entry.uuid ?? "nil")")
            logger.info("     - Script ID: \(entry.scriptId?.description ?? "nil")")
            logger.info("     - Script UUID: \(entry.scriptUUID ?? "nil")")
            logger.info("     - Script Number: \(entry.scriptNumber ?? "nil")")
            logger.info("     - Patient Name: \(entry.patientName ?? "nil")")
            logger.info("     - Caller Name: \(entry.callerName ?? "nil")")
            logger.info("     - Clinic Slug: \(entry.clinicSlug ?? "nil")")
            logger.info("     - Clinic Name: \(entry.clinicName ?? "nil")")
            logger.info("     - Room Name: \(entry.roomName ?? "nil")")
            logger.info("     - Created At: \(entry.createdAt ?? "nil")")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let mapped: [QueueItem] = entries.map { e in
            // Align ID strategy with realtime: prefer script_uuid, else "script_\(script_id)", else uuid, else id
            let id: String = {
                if let su = e.scriptUUID, !su.isEmpty { return su }
                if let sn = e.scriptNumber, !sn.isEmpty { return sn }
                if let sid = e.scriptId { return "script_\(sid)" }
                if let u = e.uuid, !u.isEmpty { return u }
                if let i = e.id, !i.isEmpty { return i }
                return UUID().uuidString
            }()
            let name = e.callerName ?? e.patientName ?? "Unknown"
            let clinic = e.clinicName ?? e.clinicSlug ?? ""
            let created = (e.createdAt.flatMap { dateFormatter.date(from: $0) }) ?? Date()
            
            // Enhanced logging for debugging scriptUUID mapping
            logger.info("🔄 Mapping entry to QueueItem:")
            logger.info("   - Original ID: \(e.id ?? "nil")")
            logger.info("   - UUID: \(e.uuid ?? "nil")")
            logger.info("   - Script UUID: \(e.scriptUUID ?? "nil")")
            logger.info("   - Script ID: \(e.scriptId?.description ?? "nil")")
            logger.info("   - Script Number: \(e.scriptNumber ?? "nil")")
            logger.info("   - Mapped ID: \(id)")
            logger.info("   - Patient Name: \(name)")
            logger.info("   - Clinic: \(clinic)")
            logger.info("   - Created: \(created)")
            
            // Try to preserve scriptUUID if available, but fall back to other identifiers
            let finalScriptUUID: String? = {
                if let su = e.scriptUUID, !su.isEmpty { return su }
                if let sn = e.scriptNumber, !sn.isEmpty { return sn }
                if let sid = e.scriptId { return "script_\(sid)" }
                return e.uuid
            }()
            
            logger.info("   - Final Script UUID: \(finalScriptUUID ?? "nil")")
            
            return QueueItem(
                id: id,
                patientName: name,
                clinic: clinic,
                createdAt: created,
                clinicSlug: e.clinicSlug,
                scriptId: e.scriptId,
                scriptUUID: finalScriptUUID,
                scriptNumber: e.scriptNumber,
                roomName: e.roomName
            )
        }
        
        // Deduplicate items before returning
        let deduplicatedItems = deduplicateQueueItems(mapped)
        
        logger.info("✅ Queue entries mapping completed: \(mapped.count) items")
        logger.info("📋 After deduplication: \(deduplicatedItems.count) items")
        logger.info("📋 Final QueueItem IDs: \(deduplicatedItems.map { $0.id })")
        
        return deduplicatedItems
    }
    
    /// Deduplicates queue items based on multiple identifier strategies
    /// Prioritizes scriptUUID, then scriptId, then other identifiers
    private func deduplicateQueueItems(_ items: [QueueItem]) -> [QueueItem] {
        logger.info("🔍 Starting deduplication of \(items.count) queue items")
        
        var seenIdentifiers: Set<String> = []
        var seenScriptUUIDs: Set<String> = []
        var seenScriptIds: Set<Int> = []
        var deduplicated: [QueueItem] = []
        var duplicatesFound = 0
        
        for item in items {
            var isDuplicate = false
            var duplicateReason = ""
            
            // Check by scriptUUID first (most reliable identifier)
            if let scriptUUID = item.scriptUUID, !scriptUUID.isEmpty {
                if seenScriptUUIDs.contains(scriptUUID) {
                    isDuplicate = true
                    duplicateReason = "scriptUUID: \(scriptUUID)"
                } else {
                    seenScriptUUIDs.insert(scriptUUID)
                }
            }
            
            // Check by scriptId if no scriptUUID or not duplicate
            if !isDuplicate, let scriptId = item.scriptId, scriptId > 0 {
                if seenScriptIds.contains(scriptId) {
                    isDuplicate = true
                    duplicateReason = "scriptId: \(scriptId)"
                } else {
                    seenScriptIds.insert(scriptId)
                }
            }
            
            // Check by mapped ID as fallback
            if !isDuplicate {
                if seenIdentifiers.contains(item.id) {
                    isDuplicate = true
                    duplicateReason = "mapped ID: \(item.id)"
                } else {
                    seenIdentifiers.insert(item.id)
                }
            }
            
            if isDuplicate {
                duplicatesFound += 1
                logger.warning("🚫 Duplicate queue item detected and removed:")
                logger.warning("   - Patient: \(item.patientName)")
                logger.warning("   - Clinic: \(item.clinic)")
                logger.warning("   - Script UUID: \(item.scriptUUID ?? "nil")")
                logger.warning("   - Script ID: \(item.scriptId?.description ?? "nil")")
                logger.warning("   - Mapped ID: \(item.id)")
                logger.warning("   - Reason: \(duplicateReason)")
            } else {
                deduplicated.append(item)
                logger.info("✅ Added unique item: \(item.patientName) (\(item.id))")
            }
        }
        
        logger.info("🎯 Deduplication completed:")
        logger.info("   - Original items: \(items.count)")
        logger.info("   - Duplicates found: \(duplicatesFound)")
        logger.info("   - Final unique items: \(deduplicated.count)")
        
        return deduplicated
    }
    
    /// Removes a queue item using the queue-remove API endpoint
    /// Note: clinicSlug is used as clinic_id in the API request since the backend requires clinic_id
    func removeQueueItem(scriptUUID: String, scriptId: Int, clinicSlug: String, clinicName: String?, callerName: String?, roomName: String?) async throws -> Bool {
        guard let user: User = keychainService.retrieve(key: "user_data", type: User.self) else {
            logger.error("❌ Failed to remove queue item: No user data found")
            throw NetworkError.unauthorized
        }
        guard let token = keychainService.retrieve(key: "auth_token", type: String.self) else {
            logger.error("❌ Failed to remove queue item: No auth token found")
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        let url = endpoints.queueRemoveURL()
        
        let requestBody: [String: Any] = [
            "doctor_user_id": user.userId,
            "doctor_user_uuid": user.userUUID ?? "",
            "clinic_id": clinicSlug, // Using clinicSlug as clinic_id since we don't have clinic_id
            "script_id": scriptId,
            "clinic_name": clinicName ?? "",
            "caller_name": callerName ?? "",
            "script_uuid": scriptUUID,
            "room_name": roomName ?? ""
        ]
        
        logger.info("🗑️ Removing queue item:")
        logger.info("   - URL: \(url)")
        logger.info("   - Script UUID: \(scriptUUID)")
        logger.info("   - Script ID: \(scriptId)")
        logger.info("   - Clinic ID: \(clinicSlug)")
        logger.info("   - Clinic Name: \(clinicName ?? "")")
        logger.info("   - Doctor User UUID: \(user.userUUID ?? "nil")")
        logger.info("   - Doctor User ID: \(user.userId)")
        
        do {
            let response: SimpleResponse = try await apiService.request(
                endpoint: url,
                method: .POST,
                body: requestBody,
                authToken: token,
                configuration: .default,
                responseType: SimpleResponse.self
            )
            
            let success = response.success
            logger.info("✅ Queue item removal response: \(success)")
            return success
        } catch {
            logger.error("❌ Failed to remove queue item: \(error)")
            throw error
        }
    }
}

// MARK: - Call Action API Service
class CallActionAPIService {
    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.cosmetictech.callaction", category: "CallActionAPIService")
    
    init(apiService: APIServiceProtocol = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }
    
    func reportCallAction(scriptId: Int, clinicSlug: String, scriptUUID: String?, action: CallAction) async throws -> EmptyResponse {
        guard let authToken = getAuthToken() else {
            throw NetworkError.unauthorized
        }
        
        let endpoints = APIConfiguration.shared.endpoints
        // Pull current user info for required fields
        let currentUser: User? = keychainService.retrieve(key: "user_data", type: User.self)
        let body = RequestBodyBuilder.callActionBody(
            scriptId: scriptId,
            clinicSlug: clinicSlug,
            action: action,
            scriptUUID: scriptUUID,
            doctorUserId: currentUser?.userId,
            doctorUserUUID: currentUser?.userUUID
        )
        
        logger.info("📞 Reporting call action: \(action.rawValue) for script \(scriptId) at clinic \(clinicSlug)")
        
        // Use aggressive configuration for call actions to ensure responsiveness
        let response: EmptyResponse = try await apiService.request(
            endpoint: endpoints.callAction,
            method: .POST,
            body: body,
            authToken: authToken,
            configuration: .aggressive,
            responseType: EmptyResponse.self
        )
        
        logger.info("✅ Call action reported successfully")
        return response
    }
    
    private func getAuthToken() -> String? {
        return keychainService.retrieve(key: "auth_token", type: String.self)
    }
}

// MARK: - API Service Extensions
extension APIService {
    /// Convenience method for GET requests
    func get<T: Codable>(
        endpoint: String,
        authToken: String? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            authToken: authToken,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for POST requests
    func post<T: Codable>(
        endpoint: String,
        body: [String: Any]?,
        authToken: String? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .POST,
            body: body,
            authToken: authToken,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for PUT requests
    func put<T: Codable>(
        endpoint: String,
        body: [String: Any]?,
        authToken: String? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .PUT,
            body: body,
            authToken: authToken,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for DELETE requests
    func delete<T: Codable>(
        endpoint: String,
        authToken: String? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .DELETE,
            body: nil,
            authToken: authToken,
            configuration: configuration,
            responseType: responseType
        )
    }
}
