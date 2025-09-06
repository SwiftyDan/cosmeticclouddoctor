//
//  CallsViewModel.swift
//  CosmeticTechMobile
//

import Foundation
import SwiftUI

@MainActor
class CallsViewModel: ObservableObject {
    @Published var callHistory: [CallHistoryItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    @Published var selectedCall: CallHistoryItem?
    @Published var isPresentingJitsi: Bool = false
    @Published var jitsiParameters: JitsiParameters?
    
    private let callHistoryService: CallHistoryServiceProtocol
    
    init(callHistoryService: CallHistoryServiceProtocol = CallHistoryService()) {
        self.callHistoryService = callHistoryService
    }
    
    func refreshCallHistory() async {
        isLoading = true
        errorMessage = nil
        await callHistoryService.refreshCallHistory()
        callHistory = callHistoryService.getCallHistory()
        isLoading = false
    }
    
    func select(call: CallHistoryItem) {
        selectedCall = call
    }
    
    func clearSelection() {
        selectedCall = nil
    }
    
    func callBack(usingDisplayName displayName: String?, email: String?) {
        guard let call = selectedCall else { return }
        // Prefer to use consultation details when script/clinic is available
        if let clinicSlug = call.clinicSlug, let scriptId = call.scriptId {
            // Open Jitsi with form bottom sheet using script/clinic params, prefer room_name
            let roomName = deriveRoomName(from: call.conferenceUrl)
            jitsiParameters = JitsiParameters(
                roomName: roomName,
                displayName: displayName,
                email: email,
                conferenceUrl: call.conferenceUrl,
                roomId: roomName,
                clinicSlug: clinicSlug,
                scriptId: scriptId
            )
            isPresentingJitsi = true
        } else {
            let conferenceURL = call.conferenceUrl
            let roomName = deriveRoomName(from: conferenceURL)
            jitsiParameters = JitsiParameters(
                roomName: roomName,
                displayName: displayName,
                email: email,
                conferenceUrl: conferenceURL,
                roomId: roomName
            )
            isPresentingJitsi = true
        }
    }
    
    // MARK: - Call Management
    func endCall() {
        print("🎥 Call ended from CallsViewModel, dismissing Jitsi view")
        isPresentingJitsi = false
        jitsiParameters = nil
    }
    
    private func deriveRoomName(from urlString: String) -> String {
        guard let comps = URLComponents(string: urlString) else {
            return "cosmetic_\(Int(Date().timeIntervalSince1970))"
        }
        let q = comps.queryItems ?? []
        if let roomName = q.first(where: { $0.name == "room_name" })?.value, !roomName.isEmpty {
            return roomName
        }
        if let roomId = q.first(where: { $0.name == "room_id" })?.value, !roomId.isEmpty {
            return roomId
        }
        if let room = q.first(where: { $0.name == "room" })?.value, !room.isEmpty {
            return room
        }
        if let scriptUUID = q.first(where: { $0.name == "script_uuid" })?.value, !scriptUUID.isEmpty {
            return scriptUUID
        }
        return "cosmetic_\(Int(Date().timeIntervalSince1970))"
    }
}

 
