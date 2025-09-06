//
//  CallHistory.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation

// MARK: - Call History Model
struct CallHistory: Identifiable, Codable {
    let id = UUID()
    let phoneNumber: String
    let displayName: String
    let callType: String
    let timestamp: Date
    let status: CallStatus
    let duration: TimeInterval?
    
    enum CallStatus: String, Codable, CaseIterable {
        case incoming = "incoming"
        case answered = "answered"
        case missed = "missed"
        case ended = "ended"
        
        var displayName: String {
            switch self {
            case .incoming:
                return "Incoming"
            case .answered:
                return "Answered"
            case .missed:
                return "Missed"
            case .ended:
                return "Ended"
            }
        }
        
        var color: String {
            switch self {
            case .incoming:
                return "blue"
            case .answered:
                return "green"
            case .missed:
                return "red"
            case .ended:
                return "gray"
            }
        }
    }
}

 