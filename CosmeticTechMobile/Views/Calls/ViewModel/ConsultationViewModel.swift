//
//  ConsultationViewModel.swift
//  CosmeticTechMobile
//

import Foundation
import SwiftUI

enum ConsultActionState: Equatable {
    case idle
    case processingApprove
    case processingReject
    case successApprove
    case successReject
    case failure(String)
}

struct ConsultationField: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let value: String
}

@MainActor
final class ConsultationViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var fields: [ConsultationField] = []
    @Published var patientSignatureURL: URL?
    @Published var nurseSignatureURL: URL?
    @Published var conferenceDisplayName: String?
    @Published var conferenceRoomName: String?
    @Published var scriptStatus: String?
    @Published var scriptProducts: String?
    @Published var actionState: ConsultActionState = .idle
    @Published var showSuccess = false
    @Published var successMessage = ""

    private let clinicSlug: String?
    private let scriptId: Int?
    private let callAPI = CallAPIService()

    init(clinicSlug: String?, scriptId: Int?) {
        self.clinicSlug = clinicSlug
        self.scriptId = scriptId
    }

    func load() async {
        guard let clinicSlug, let scriptId else {
            // Show error message when required data is missing
            error = "Consultation details not available. Missing clinic or script information."
            print("❌ Cannot load consultation: clinicSlug=\(clinicSlug ?? "nil"), scriptId=\(scriptId?.description ?? "nil")")
            return
        }
        isLoading = true
        error = nil
        do {
            print("📋 Loading consultation: clinicSlug=\(clinicSlug), scriptId=\(scriptId)")
            let res = try await callAPI.fetchConsultationVideo(clinicSlug: clinicSlug, scriptId: scriptId)
            conferenceDisplayName = res.conference.displayName
            conferenceRoomName = res.conference.roomName
            scriptStatus = res.data.scriptStatus
            scriptProducts = res.data.scriptProducts
            var items: [ConsultationField] = []
            items.append(.init(name: "Script #", value: res.data.scriptNumber))
            items.append(.init(name: "Patient", value: res.data.patientName))
            items.append(.init(name: "Date of birth", value: formatDisplayDate(res.data.dateOfBirth)))
            items.append(.init(name: "Doctor", value: res.data.doctorName))
            items.append(.init(name: "Nurse", value: res.data.nurseName))
            items.append(.init(name: "Consultation date", value: formatDisplayDate(res.data.consultationDate)))
            for qa in res.data.medicalConsultation { items.append(.init(name: qa.label, value: qa.answer)) }
            items.append(.init(name: "Consent Photos", value: res.data.patientConsentPhotographs))
            items.append(.init(name: "Consent Treatment", value: res.data.patientConsentToTreatment))
            if let p = res.data.patientSignature, let url = URL(string: p) { patientSignatureURL = url }
            if let n = res.data.nurseSignature, let url = URL(string: n) { nurseSignatureURL = url }
            fields = items
            print("✅ Consultation loaded successfully with \(items.count) fields")
            print("📋 Script Status: \(scriptStatus ?? "nil")")
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to load consultation: \(error)")
        }
        isLoading = false
    }

    func updateStatus(_ status: Int) async {
        guard let clinicSlug, let scriptId else { return }
        actionState = (status == 1) ? .processingApprove : .processingReject
        do {
            _ = try await callAPI.updateConsultationStatus(scriptId: scriptId, clinicSlug: clinicSlug, status: status)
            successMessage = status == 1 ? "Consultation approved" : "Consultation rejected"
            showSuccess = true
            actionState = (status == 1) ? .successApprove : .successReject
            
            // Refresh consultation data to get updated status and hide buttons
            print("📋 Refreshing consultation data after status update")
            await load()
        } catch {
            self.error = error.localizedDescription
            actionState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Date helpers
    private func formatDisplayDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = parseDate(trimmed) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "MMMM d, yyyy"
            return df.string(from: date)
        }
        return raw
    }

    private func parseDate(_ value: String) -> Date? {
        let fmts = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: value) { return d }
        }
        if let d = ISO8601DateFormatter().date(from: value) { return d }
        return nil
    }
}


