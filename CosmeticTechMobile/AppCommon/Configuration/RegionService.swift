//
//  RegionService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import CoreTelephony
import SwiftUI

// MARK: - Region Service Protocol
protocol RegionServiceProtocol {
    func isCallKitEnabled() -> Bool
    func getUserRegion() -> String
    func isUserInChina() -> Bool
    func getRegionDisplayName() -> String
    func getDetailedRegionInfo() -> [String: String]
    func testRegionDetection() -> String
}

// MARK: - Region Service Implementation
class RegionService: ObservableObject, RegionServiceProtocol {
    static let shared = RegionService()
    
    // Published properties for SwiftUI binding
    @Published var currentRegion: String = ""
    
    private let telephonyInfo = CTTelephonyNetworkInfo()
    private let locale = Locale.current
    
    private init() {
        // Initialize published properties
        self.currentRegion = getUserRegion()
        
        // Initialize region detection (logging removed for production)
        _ = isUserInChina()
        _ = isCallKitEnabled()
    }
    
    /// Determines if CallKit functionality should be enabled based on user's region
    /// CallKit is disabled for users in China per Apple's requirements
    func isCallKitEnabled() -> Bool {
        return !isUserInChina()
    }
    
    /// Gets the user's current region code
    func getUserRegion() -> String {
        // First try to get from carrier info (most accurate for mobile)
        if let carrier = telephonyInfo.subscriberCellularProvider,
           let countryCode = carrier.isoCountryCode,
           !countryCode.isEmpty {
            let region = countryCode.uppercased()
            self.currentRegion = region
            return region
        }
        
        // Fallback to locale region code
        if let regionCode = locale.regionCode {
            self.currentRegion = regionCode
            return regionCode
        }
        
        // Final fallback to system region
        let fallbackRegion = locale.identifier.components(separatedBy: "_").last ?? "US"
        self.currentRegion = fallbackRegion
        return fallbackRegion
    }
    
    /// Checks if the user is currently in China
    func isUserInChina() -> Bool {
        let region = getUserRegion()
        let isChina = region == "CN" || region == "CHN"
        print("🇨🇳 China check for region \(region): \(isChina)")
        return isChina
    }
    
    /// Gets a human-readable display name for the current region
    func getRegionDisplayName() -> String {
        let region = getUserRegion()
        
        // Map common region codes to display names
        let regionNames: [String: String] = [
            "US": "United States",
            "CA": "Canada",
            "GB": "United Kingdom",
            "AU": "Australia",
            "DE": "Germany",
            "FR": "France",
            "JP": "Japan",
            "KR": "South Korea",
            "CN": "China",
            "CHN": "China",
            "HK": "Hong Kong",
            "TW": "Taiwan",
            "SG": "Singapore",
            "IN": "India",
            "BR": "Brazil",
            "MX": "Mexico",
            "PH": "Philippines"
        ]
        
        return regionNames[region] ?? region
    }
    
    /// Gets detailed region information for debugging
    func getDetailedRegionInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        // Carrier info
        if let carrier = telephonyInfo.subscriberCellularProvider {
            info["carrier_name"] = carrier.carrierName ?? "Unknown"
            info["carrier_country"] = carrier.isoCountryCode ?? "Unknown"
            info["carrier_mcc"] = carrier.mobileCountryCode ?? "Unknown"
            info["carrier_mnc"] = carrier.mobileNetworkCode ?? "Unknown"
        }
        
        // Locale info
        info["locale_identifier"] = locale.identifier
        info["locale_language"] = locale.languageCode ?? "Unknown"
        info["locale_region"] = locale.regionCode ?? "Unknown"
        info["locale_currency"] = locale.currencyCode ?? "Unknown"
        
        // System info
        info["system_region"] = getUserRegion()
        info["is_china"] = String(isUserInChina())
        info["callkit_enabled"] = String(isCallKitEnabled())
        
        return info
    }
    
    /// Test method for development and debugging
    func testRegionDetection() -> String {
        let region = getUserRegion()
        let isChina = isUserInChina()
        let callKitEnabled = isCallKitEnabled()
        
        let result = """
        🌍 Region Detection Test Results:
        
        📱 Detected Region: \(region)
        🏷️ Region Name: \(getRegionDisplayName())
        🇨🇳 Is China: \(isChina ? "Yes" : "No")
        📞 CallKit Enabled: \(callKitEnabled ? "Yes" : "No")
        
        📊 Detailed Info:
        \(getDetailedRegionInfo().map { "   \($0.key): \($0.value)" }.joined(separator: "\n"))
        
        \(callKitEnabled ? "✅ CallKit will work normally" : "⚠️ CallKit disabled - using fallback UI")
        """
        
        print(result)
        return result
    }
}
