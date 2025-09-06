//
//  DeviceOrientationService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import UIKit

// MARK: - Device Orientation & Layout Service
class DeviceOrientationService {
    
    // MARK: - Singleton
    static let shared = DeviceOrientationService()
    
    private init() {}
    
    // MARK: - Device Type Detection
    var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var isIPhone: Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
    
    var isMac: Bool {
        return UIDevice.current.userInterfaceIdiom == .mac
    }
    
    // MARK: - Screen Size Detection
    var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }
    
    var isLargeScreen: Bool {
        return isIPad || screenSize.width >= 768
    }
    
    // MARK: - Orientation Support
    var supportsLandscape: Bool {
        return isIPad || UIDevice.current.orientation.isLandscape
    }
    
    // MARK: - Layout Constants
    var horizontalPadding: CGFloat {
        return isIPad ? 40 : 20
    }
    
    var maxContentWidth: CGFloat {
        return isIPad ? 800 : screenSize.width
    }
    
    var cornerRadius: CGFloat {
        return isIPad ? 20 : 16
    }
    
    var spacing: CGFloat {
        return isIPad ? 32 : 24
    }
    
    // MARK: - Font Sizes
    var titleFontSize: CGFloat {
        return isIPad ? 34 : 28
    }
    
    var headlineFontSize: CGFloat {
        return isIPad ? 28 : 22
    }
    
    var bodyFontSize: CGFloat {
        return isIPad ? 18 : 16
    }
    
    var captionFontSize: CGFloat {
        return isIPad ? 14 : 12
    }
    
    // MARK: - Component Sizes
    var buttonHeight: CGFloat {
        return isIPad ? 56 : 44
    }
    
    var iconSize: CGFloat {
        return isIPad ? 24 : 20
    }
    
    var avatarSize: CGFloat {
        return isIPad ? 80 : 60
    }
    
    var logoSize: CGFloat {
        return isIPad ? 128 : 96
    }
    
    // MARK: - Animation & Visual
    var shadowRadius: CGFloat {
        return isIPad ? 12 : 8
    }
    
    var progressScale: CGFloat {
        return isIPad ? 1.5 : 1.2
    }
}
