//
//  DeviceService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import UIKit

// MARK: - Device Info
struct DeviceInfo {
    let phone: String
    let tokenCode: String
    let platform: String
    let osVersion: String
    let manufacturer: String
    let brand: String
}

// MARK: - Device Service Protocol
protocol DeviceServiceProtocol {
    func getDeviceInfo() -> DeviceInfo
    func getTokenCode() -> String
    func getTokenCodeWithRetry() async -> String
}

// MARK: - Device Service Implementation
class DeviceService: DeviceServiceProtocol {
    
    func getDeviceInfo() -> DeviceInfo {
        return DeviceInfo(
            phone: getPhoneNumber(),
            tokenCode: getTokenCode(),
            platform: "ios",
            osVersion: getOSVersion(),
            manufacturer: getManufacturer(),
            brand: getBrand()
        )
    }
    
    func getTokenCode() -> String {
        // Always return the REAL VoIP push token; never return a placeholder here
        let token = VoIPPushHandler.shared.getCurrentVoIPToken()
        if let token = token, !token.isEmpty {
            print("🔍 DeviceService.getTokenCode() called - Token: \(token)")
            return token
        }
        return "" // Explicitly empty to force callers to retry/wait
    }
    
    func getTokenCodeWithRetry() async -> String {
        // Try to get VoIP token with retry mechanism; do not return placeholder
        for attempt in 1...10 {
            let token = VoIPPushHandler.shared.getCurrentVoIPToken()
            
            if let token = token, !token.isEmpty {
                print("✅ VoIP token retrieved on attempt \(attempt): \(token)")
                return token
            }
            
            print("⏳ VoIP token not ready, attempt \(attempt)/10")
            
            if attempt < 10 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        // Last chance: use cached token if present (from previous session)
        if let cached: String = KeychainService().retrieve(key: "voip_token", type: String.self), !cached.isEmpty {
            print("✅ Using cached VoIP token from keychain")
            return cached
        }
        return "" // Signal failure so caller can block/login gating
    }
    
    // MARK: - Private Methods
    private func getPhoneNumber() -> String {
        // In a real app, you might get this from user input or contacts
        // For now, we'll use a placeholder
        return "+63912345678"
    }
    
    private func getOSVersion() -> String {
        return UIDevice.current.systemVersion
    }
    
    private func getManufacturer() -> String {
        return "Apple"
    }
    
    private func getBrand() -> String {
        return "iPhone"
    }
    


    

} 