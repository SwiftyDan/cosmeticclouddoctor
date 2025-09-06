//
//  User.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation

// MARK: - User Model
struct User: Codable, Identifiable {
    let userUUID: String?
    let userId: Int
    let doctorUserId: Int?
    let doctorName: String
    let email: String
    let phone: String?
    let devices: [Device]?
    
    var id: String { String(userId) }
    var name: String? { 
        if doctorName.hasPrefix("Dr. ") {
            return doctorName
        } else {
            return "\(doctorName)"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case userUUID = "user_uuid"
        case userId = "user_id"
        case doctorUserId = "doctor_user_id"
        case doctorName = "doctor_name"
        case email
        case phone
        case devices
    }
}

// MARK: - Device Model
struct Device: Codable {
    let platform: String
    let osVersion: String
    let brand: String
    let manufacturer: String
    let deviceName: String?
    let isRegistered: Bool
    let dateRegistered: String
    let phone: String?
    let tokenCode: String
    
    enum CodingKeys: String, CodingKey {
        case platform
        case osVersion = "os_version"
        case brand
        case manufacturer
        case deviceName = "device_name"
        case isRegistered = "isRegistered"
        case dateRegistered = "dateRegistered"
        case phone
        case tokenCode = "token_code"
    }
}

// MARK: - Login Request
struct LoginRequest: Codable {
    let email: String
    let password: String
}

// MARK: - Login Response
struct LoginResponse: Codable {
    let user: User
    let token: String
}

// MARK: - Device Registration Request
struct DeviceRegistrationRequest: Codable {
    let phone: String
    let tokenCode: String
    let platform: String
    let osVersion: String
    let isRegistered: Bool
    let manufacturer: String
    let brand: String
    
    enum CodingKeys: String, CodingKey {
        case phone
        case tokenCode = "token_code"
        case platform
        case osVersion = "os_version"
        case isRegistered = "isRegistered"
        case manufacturer
        case brand
    }
}

// MARK: - Device Registration Response
struct DeviceRegistrationResponse: Codable {
    let success: Bool?
    let message: String?
    let deviceId: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case deviceId = "device_id"
    }
} 
