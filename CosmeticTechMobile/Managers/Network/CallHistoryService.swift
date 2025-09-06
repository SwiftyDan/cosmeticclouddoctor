//
//  CallHistoryService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import Foundation
import SwiftUI
import os.log

// MARK: - Call History Models
struct CallHistoryItem: Identifiable, Codable {
    let id: Int
    let conferenceUrl: String
    let calledAt: String
    let acceptedAt: String?
    let rejectedAt: String?
    let callerName: String
    let calledFromClinic: String
    let clinicSlug: String?
    let scriptId: Int?
    let scriptNumber: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case conferenceUrl = "conference_url"
        case calledAt = "called_at"
        case acceptedAt = "accepted_at"
        case rejectedAt = "rejected_at"
        case callerName = "caller_name"
        case calledFromClinic = "called_from_clinic"
        case clinicSlug = "clinic_slug"
        case scriptId = "script_id"
        case scriptNumber = "script_number"
    }
    
    // Computed properties for better UI display
    var callStatus: String {
        let accepted = !(acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let rejected = !(rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if rejected { return "rejected" }
        if accepted { return "approved" }
        return "queue"
    }
    
    var callDate: String {
        return calledAt
    }
    
    var patientName: String {
        return callerName
    }
    
    var doctorName: String {
        return "Doctor" // This could be extracted from conference URL if needed
    }
    
    var clinicName: String {
        return calledFromClinic
    }
    
    var callDuration: Int? {
        guard let acceptedAt = acceptedAt else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let calledDate = dateFormatter.date(from: calledAt),
           let acceptedDate = dateFormatter.date(from: acceptedAt) {
            return Int(acceptedDate.timeIntervalSince(calledDate))
        }
        
        return nil
    }
}

struct CallHistoryResponse: Codable {
    let data: [CallHistoryItem]
}

// MARK: - Call History Service Protocol
protocol CallHistoryServiceProtocol {
    func fetchCallHistory(tokenCode: String?) async throws -> [CallHistoryItem]
    func getCallHistory() -> [CallHistoryItem]
    func refreshCallHistory() async
}

// MARK: - Call History Service Implementation
class CallHistoryService: ObservableObject, CallHistoryServiceProtocol {
    @Published var callHistory: [CallHistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkService: NetworkServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let deviceService: DeviceServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.cosmetictech.callhistory", category: "CallHistoryService")
    
    init(networkService: NetworkServiceProtocol = NetworkService(baseURL: APIConfiguration.shared.endpoints.baseURL),
         keychainService: KeychainServiceProtocol = KeychainService(),
         deviceService: DeviceServiceProtocol = DeviceService()) {
        self.networkService = networkService
        self.keychainService = keychainService
        self.deviceService = deviceService
    }
    
    func fetchCallHistory(tokenCode: String? = nil) async throws -> [CallHistoryItem] {
        // Get access token
        guard let accessToken = keychainService.retrieve(key: "auth_token", type: String.self) else {
            throw NetworkError.unauthorized
        }
        
        // Validate token format
        if accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NetworkError.unauthorized
        }
        
        // Build URL with optional token_code parameter
        var urlComponents = URLComponents(string: "\(APIConfiguration.shared.endpoints.baseURL)/call-history")!
        
        if let tokenCode = tokenCode {
            urlComponents.queryItems = [URLQueryItem(name: "token_code", value: tokenCode)]
        }
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Handle token that might already have "Bearer " prefix
        let authHeader = accessToken.hasPrefix("Bearer ") ? accessToken : "Bearer \(accessToken)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Log HTTP status and payload size
            if let httpResponse = response as? HTTPURLResponse {
                let sizeKB = String(format: "%.1fKB", Double(data.count) / 1024.0)
                logger.info("📥 Call history response status=\(httpResponse.statusCode, privacy: .public) size=\(sizeKB, privacy: .public)")
            }
            if let raw = String(data: data, encoding: .utf8) {
                let maxLen = 8000
                let snippet = raw.count > maxLen ? String(raw.prefix(maxLen)) + "… (truncated)" : raw
                logger.debug("📄 Call history raw: \(snippet, privacy: .private)")
            }
            
            // Check for specific error status codes
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw NetworkError.unauthorized
                } else if httpResponse.statusCode == 403 {
                    throw NetworkError.forbidden
                } else if httpResponse.statusCode >= 500 {
                    throw NetworkError.serverError("Server error: \(httpResponse.statusCode)")
                }
            }
            
            // Check if response is empty
            if data.isEmpty {
                throw NetworkError.serverError("Empty response from server")
            }
            
            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            
            // Some backends return an empty array directly ([]). Try that first.
            if let array = try? decoder.decode([CallHistoryItem].self, from: data) {
                logger.info("✅ Parsed call history (array) count=\(array.count, privacy: .public)")
                return array
            }
            
            // Try to parse as CallHistoryResponse
            let callHistoryResponse = try decoder.decode(CallHistoryResponse.self, from: data)
            let callHistoryItems = callHistoryResponse.data
            logger.info("✅ Parsed call history (wrapped) count=\(callHistoryItems.count, privacy: .public)")
            
            return callHistoryItems
            
        } catch {
            throw error
        }
    }
    
    func getCallHistory() -> [CallHistoryItem] {
        return callHistory
    }
    
    // MARK: - Debug Methods
    func testAPIConnection() async {
        // Check if we have a token
        if let token = keychainService.retrieve(key: "auth_token", type: String.self) {
            // Token found - could log to analytics
        } else {
            // No token found - could log to analytics
        }
        
        // Check available keys
        let keys = keychainService.getAllKeys()
        
        // Test the endpoint
        let endpoint = APIConfiguration.shared.endpoints.callHistory
        
        // Try to make a simple request
        do {
            let history = try await fetchCallHistory()
            // API test successful - could log to analytics
        } catch {
            // API test failed - could log to analytics
        }
    }
    
    @MainActor
    func refreshCallHistory() async {
        // Cancel any in-flight request to avoid -999 errors, then start a fresh one
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            await self?._refreshCallHistory()
        }
        await refreshTask?.value
    }

    @MainActor
    private func _refreshCallHistory() async {
        isLoading = true
        errorMessage = nil

        do {
            // Prefer fetching the full call history first
            let allHistory = try await fetchCallHistory()
            callHistory = allHistory
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                isLoading = false
                return
            }
            // Fallback to device-specific history (token scoped)
            do {
                let tokenCode = try await deviceService.getTokenCodeWithRetry()
                let deviceHistory = try await fetchCallHistory(tokenCode: tokenCode)
                callHistory = deviceHistory
            } catch {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    isLoading = false
                    return
                }
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}

// MARK: - Network Error Extension
extension NetworkError {
    static func apiError(_ message: String) -> NetworkError {
        return .serverError(message)
    }
}
