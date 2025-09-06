//
//  CallDetailsView.swift
//  CosmeticTechMobile
//

import SwiftUI
import SkeletonView

struct CallDetailsView: View {
    let call: CallHistoryItem
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var details: CallAPIService.ConsultationVideoResponse?
    private let api = CallAPIService()
    private let labelColumnWidth: CGFloat = 140
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if isLoading {
                    AnimatedCallDetailsSkeletonView()
                        .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    ErrorView(message: errorMessage) { Task { await load() } }
                        .frame(maxWidth: .infinity)
                } else if let details {
                    detailsCards(for: details)
                }
            }
            .padding(20)
        }
        .navigationTitle("Call Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    
    // MARK: - UI Sections
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(call.callerName)
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                StatusBadge(status: statusText, tint: statusColor)
            }
            Text("From: \(call.calledFromClinic)").foregroundColor(.secondary)
                        Text("Called at: \(call.calledAt.asRelativeTimeFromServer())").foregroundColor(.secondary)
        if let acceptedAt = call.acceptedAt, !acceptedAt.isEmpty {
            Text("Accepted at: \(acceptedAt.asRelativeTimeFromServer())").foregroundColor(.secondary)
        }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
    
    @ViewBuilder
    private func detailsCards(for res: CallAPIService.ConsultationVideoResponse) -> some View {
        VStack(spacing: 16) {
            // Meta chip row (room name)
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group").foregroundStyle(.blue)
                Text("Room: \(res.conference.roomName)")
                    .font(.subheadline)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.blue.opacity(0.2), radius: 2, x: 0, y: 1)
                Spacer()
            }
            
            // Consultation details card
            sectionCard(title: "Consultation Details", icon: "doc.text") {
                keyValueRow("Script #", res.data.scriptNumber)
                keyValueRow("Patient", res.data.patientName)
                keyValueRow("Date of birth", res.data.dateOfBirth)
                keyValueRow("Doctor", res.data.doctorName)
                keyValueRow("Nurse", res.data.nurseName)
                keyValueRow("Consultation date", res.data.consultationDate)
                keyValueRow("Consent Photos", res.data.patientConsentPhotographs)
                keyValueRow("Consent Treatment", res.data.patientConsentToTreatment)
            }
            
            // Medical consultation QA card
            sectionCard(title: "Medical Consultation", icon: "stethoscope") {
                ForEach(res.data.medicalConsultation.indices, id: \.self) { idx in
                    let qa = res.data.medicalConsultation[idx]
                    keyValueRow(qa.label, qa.answer)
                }
            }
            
            // Script Products card (if available)
            if let scriptProducts = res.data.scriptProducts, !scriptProducts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sectionCard(title: "Script Products", icon: "pills") {
                    HTMLContentView(
                        htmlContent: scriptProducts,
                        title: "",
                        height: 250
                    )
                }
            }
            
            // Signatures card
            sectionCard(title: "Signatures", icon: "signature") {
                HStack(alignment: .top, spacing: 16) {
                    SignatureCard(title: "Patient Signature", urlString: res.data.patientSignature)
                    SignatureCard(title: "Nurse Signature", urlString: res.data.nurseSignature)
                }
            }
        }
    }
    
    private func keyValueRow(_ name: String, _ rawValue: String) -> some View {
        let value = formattedDisplayValue(name: name, raw: rawValue)
        return HStack(alignment: .top, spacing: 16) {
            // Label left
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)
            // Answer right
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        }
        .padding(.vertical, 6)
        .overlay(
            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.horizontal, 4),
            alignment: .bottom
        )
    }
    


    // MARK: - Formatting Helpers
    private func formattedDisplayValue(name: String, raw: String) -> String {
        // Normalize whitespace
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // If field likely holds a date, try formatting
        let lower = name.lowercased()
        if lower.contains("date of birth") || lower.contains("consultation date") || isDateLike(trimmed) {
            if let d = parseDate(trimmed) {
                return formatDate(d, includeTime: hasTimeComponent(trimmed))
            }
        }
        return trimmed
    }

    private func isDateLike(_ value: String) -> Bool {
        // Quick heuristics: yyyy-mm-dd or yyyy-mm-dd hh:mm:ss or ISO8601
        return value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil ||
               value.range(of: "^\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}(:\\d{2})?$", options: .regularExpression) != nil ||
               value.contains("T") && value.contains("-")
    }

    private func hasTimeComponent(_ value: String) -> Bool {
        return value.contains(":")
    }

    private func parseDate(_ value: String) -> Date? {
        // Try common server formats
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
        // Try ISO8601
        if let d = ISO8601DateFormatter().date(from: value) { return d }
        return nil
    }

    private func formatDate(_ date: Date, includeTime: Bool) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = includeTime ? "MMMM d, yyyy h:mm a" : "MMMM d, yyyy"
        return df.string(from: date)
    }

    // MARK: - Section Card Wrapper
    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Spacer()
            }
            VStack(spacing: 0) { content() }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
    
    private var statusText: String {
        // Priority: explicit details status -> computed call status
        if let s = details?.data.scriptStatus, !s.isEmpty { return s }
        // If neither accepted nor rejected, show Queue
        let acceptedEmpty = call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let rejectedEmpty = call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        if acceptedEmpty && rejectedEmpty { return "Queue" }
        return call.callStatus.capitalized
    }
    
    private var statusColor: Color {
        let s = statusText.lowercased()
        if s.contains("queue") { return .orange }
        if s.contains("reject") { return .red }
        if s.contains("approve") { return .green }
        if s.contains("await") { return .orange }
        return .secondary
    }
    
    // MARK: - Load
    @MainActor
    private func load() async {
        guard let clinic = call.clinicSlug, let script = call.scriptId else { return }
        isLoading = true
        errorMessage = nil
        do {
            let res = try await api.fetchConsultationVideo(clinicSlug: clinic, scriptId: script)
            details = res
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    // MARK: - Skeleton Loading View
    private var skeletonLoadingView: some View {
        VStack(spacing: 20) {
            // Skeleton for consultation details
            VStack(alignment: .leading, spacing: 16) {
                // Skeleton for title
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 200, height: 24)
                    .cornerRadius(6)
                
                // Skeleton for key-value rows
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 16)
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 200, height: 16)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            )
            
            // Skeleton for medical consultation
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 180, height: 24)
                    .cornerRadius(6)
                
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 150, height: 16)
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 250, height: 16)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
}

// MARK: - Call Details Skeleton View
struct AnimatedCallDetailsSkeletonView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Skeleton for consultation details
            VStack(alignment: .leading, spacing: 16) {
                // Skeleton for title
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 200, height: 24)
                    .cornerRadius(6)
                
                // Skeleton for key-value rows
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 16)
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 200, height: 16)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            )
            
            // Skeleton for medical consultation
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 180, height: 24)
                    .cornerRadius(6)
                
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 150, height: 16)
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 250, height: 16)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
}

private struct StatusBadge: View {
    let status: String
    let tint: Color
    var body: some View {
        Text(status)
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

private struct SignatureCard: View {
    let title: String
    let urlString: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                } placeholder: { ProgressView() }
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
            } else {
                Text("No signature").font(.footnote).foregroundColor(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }
}
