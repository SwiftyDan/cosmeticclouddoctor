//
//  CallRowView.swift
//  CosmeticTechMobile
//

import SwiftUI

struct CallHistoryCompactRowView: View {
    let call: CallHistoryItem
    let onTap: () -> Void
    let onCallBack: () -> Void
    var showCallBackButton: Bool = true
    
    private var status: RowStatus {
        // Check if acceptedAt has a value
        let isAccepted = !(call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        // Check if rejectedAt has a value
        let isRejected = !(call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        
        if isRejected {
            return .rejected
        } else if isAccepted {
            return .approved
        } else {
            return .queue
        }
    }
    private var statusText: String {
        switch status {
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .queue: return "Queue"
        }
    }
    private var statusColor: Color { status.color }
    
    private var timeText: String { call.calledAt.asRelativeTimeFromServer() }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading status icon (green check for approved, red X for rejected, orange phone for queue)
            Image(systemName: status == .approved ? "checkmark.circle.fill" : (status == .rejected ? "xmark.circle.fill" : "phone.fill"))
                .font(.title3)
                .foregroundColor(status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(call.callerName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                if let sn = call.scriptNumber, !sn.isEmpty {
                    Text("#\(sn)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(call.calledFromClinic)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
                Text(timeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if showCallBackButton {
                    Button(action: onCallBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                            Text("Call Back")
                        }
                        .font(.caption2)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.vertical, 8)
    }
    
    private enum RowStatus {
        case approved, rejected, queue
        var color: Color {
            switch self {
            case .approved: return .green
            case .rejected: return .red
            case .queue: return .orange
            }
        }
    }
}
