//
//  APIRequestBuilder.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import Foundation
import UIKit

// MARK: - Request Headers
struct APIHeaders {
    static let contentType = "Content-Type"
    static let authorization = "Authorization"
    static let accept = "Accept"
    static let userAgent = "User-Agent"
    
    static let jsonContentType = "application/json"
    static let acceptJson = "application/json"
    
    static func bearerToken(_ token: String) -> String {
        return "Bearer \(token)"
    }
}

// MARK: - API Request Builder
class APIRequestBuilder {
    
    // MARK: - Basic Request
    static func buildRequest(
        url: URL,
        method: HTTPMethod,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Set default headers
        request.setValue(APIHeaders.jsonContentType, forHTTPHeaderField: APIHeaders.contentType)
        request.setValue(APIHeaders.acceptJson, forHTTPHeaderField: APIHeaders.accept)
        
        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add body for POST/PUT requests
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                print("❌ Failed to serialize request body: \(error)")
            }
        }
        
        return request
    }
    
    // MARK: - Authenticated Request
    static func buildAuthenticatedRequest(
        url: URL,
        method: HTTPMethod,
        authToken: String,
        body: [String: Any]? = nil,
        additionalHeaders: [String: String]? = nil
    ) -> URLRequest {
        var headers = additionalHeaders ?? [:]
        headers[APIHeaders.authorization] = APIHeaders.bearerToken(authToken)
        
        return buildRequest(
            url: url,
            method: method,
            body: body,
            headers: headers
        )
    }
    
    // MARK: - Request with Device Info
    static func buildRequestWithDeviceInfo(
        url: URL,
        method: HTTPMethod,
        authToken: String? = nil,
        body: [String: Any]? = nil,
        additionalHeaders: [String: String]? = nil
    ) -> URLRequest {
        var headers = additionalHeaders ?? [:]
        
        // Add device info headers
        headers["Device-Model"] = UIDevice.current.model
        headers["Device-OS"] = UIDevice.current.systemVersion
        headers["App-Version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        // Add authorization if provided
        if let authToken = authToken {
            headers[APIHeaders.authorization] = APIHeaders.bearerToken(authToken)
        }
        
        return buildRequest(
            url: url,
            method: method,
            body: body,
            headers: headers
        )
    }
}

// MARK: - Request Body Builders
class RequestBodyBuilder {
    
    // MARK: - Login Request
    static func loginBody(email: String, password: String) -> [String: Any] {
        return [
            "email": email,
            "password": password
        ]
    }
    
    // MARK: - Device Registration Request
    static func deviceRegistrationBody(
        phone: String,
        tokenCode: String,
        platform: String,
        osVersion: String,
        isRegistered: Bool,
        manufacturer: String,
        brand: String
    ) -> [String: Any] {
        return [
            "phone": phone,
            "token_code": tokenCode,
            "platform": platform,
            "os_version": osVersion,
            "isRegistered": isRegistered,
            "manufacturer": manufacturer,
            "brand": brand
        ]
    }
    
    // MARK: - Logout Request
    static func logoutBody(tokenCode: String) -> [String: Any] {
        return [
            "token_code": tokenCode.isEmpty ? "VOIP_TOKEN_PLACEHOLDER" : tokenCode
        ]
    }
    
    // MARK: - Call Creation Request
    static func callCreationBody(
        phoneNumber: String,
        callType: String,
        conferenceUrl: String? = nil
    ) -> [String: Any] {
        var body: [String: Any] = [
            "phone_number": phoneNumber,
            "call_type": callType
        ]
        
        if let conferenceUrl = conferenceUrl {
            body["conference_url"] = conferenceUrl
        }
        
        return body
    }
    
    // MARK: - Call Action Request
    static func callActionBody(
        scriptId: Int,
        clinicSlug: String,
        action: CallAction,
        scriptUUID: String?,
        doctorUserId: Int?,
        doctorUserUUID: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "script_id": scriptId,
            // Backend expects clinic_id; we map slug to id as used elsewhere
            "clinic_id": clinicSlug,
            "action": action.rawValue
        ]
        if let scriptUUID = scriptUUID, !scriptUUID.isEmpty {
            body["script_uuid"] = scriptUUID
        }
        if let doctorUserUUID = doctorUserUUID, !doctorUserUUID.isEmpty {
            body["doctor_user_uuid"] = doctorUserUUID
        }
        if let doctorUserId = doctorUserId {
            body["doctor_user_id"] = doctorUserId
        }
        return body
    }
}
