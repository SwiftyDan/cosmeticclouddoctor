//
//  RegionServiceFactory.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation

// MARK: - Region Service Factory
class RegionServiceFactory {
    static func createRegionService() -> RegionServiceProtocol {
        return RegionService.shared
    }
}
