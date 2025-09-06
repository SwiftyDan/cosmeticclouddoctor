//
//  HomeView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI
import SkeletonView

struct HomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = HomeViewModel()
    @Binding var selectedTab: Int
    private let deviceService = DeviceOrientationService.shared
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
            
            // Content
            ScrollView {
                VStack(spacing: deviceService.isIPad ? 20 : 16) {
                    // Welcome Section
                    WelcomeSectionView(user: authManager.currentUser)
                    
                    // Queue List (Realtime)
                    QueueListSectionView(items: viewModel.queueList, isLoading: viewModel.isLoadingQueue, viewModel: viewModel)

                    // Recent Calls Section
                    RecentCallsSectionView(
                        calls: viewModel.callHistory,
                        isLoading: viewModel.isLoadingCallHistory,
                        selectedTab: $selectedTab
                    )

                    // Minimal bottom spacing for better scroll experience
                    Spacer(minLength: deviceService.isIPad ? 40 : 20)
                }
                .padding(.horizontal, deviceService.horizontalPadding)
                .padding(.top, deviceService.isIPad ? 40 : 20)
                .padding(.bottom, deviceService.isIPad ? 40 : 20)
                .frame(maxWidth: deviceService.maxContentWidth)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await viewModel.refreshCallHistory()
                await viewModel.refreshQueueFromAPI()
            }
        }
        .fullScreenCover(isPresented: $viewModel.isPresentingJitsi) {
            if let params = viewModel.jitsiParameters {
                JitsiMeetConferenceView(
                    roomName: params.roomName,
                    displayName: params.displayName,
                    email: params.email,
                    conferenceUrl: params.conferenceUrl,
                    roomId: params.roomId,
                    clinicSlug: params.clinicSlug,
                    scriptId: params.scriptId,
                    onEndCall: {
                        // Handle consultation ending and automatically remove queue item
                        viewModel.handleConsultationEnded()
                        // Dismiss the Jitsi view
                        viewModel.isPresentingJitsi = false
                    }
                )
                .onDisappear {
                    // Clean up consultation state if view is dismissed without ending call
                    viewModel.cleanupConsultation()
                }
            }
        }
    }
}

// MARK: - Queue List Section
struct QueueListSectionView: View {
    let items: [QueueItem]
    let isLoading: Bool
    let viewModel: HomeViewModel
    @EnvironmentObject private var authManager: AuthManager
    
    private let deviceService = DeviceOrientationService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue list")
                    .font(.system(size: deviceService.headlineFontSize, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, deviceService.isIPad ? 24 : 16)
            .padding(.top, deviceService.isIPad ? 24 : 16)
            
            if isLoading {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            // Skeleton for avatar
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                // Skeleton for title
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 120, height: 16)
                                
                                // Skeleton for subtitle
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 80, height: 12)
                            }
                            
                            Spacer()
                            
                            // Skeleton for button
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 32)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.vertical, 20)
            } else if items.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.questionmark",
                    title: "No queued items",
                    subtitle: "Patients waiting to be served will appear here.",
                    iconSize: 60
                )
                .padding(.vertical, 20)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        QueueRowView(
                            item: item, 
                            position: index + 1, 
                            onCallBack: {
                                // Start consultation using the new method
                                viewModel.startQueueConsultation(for: item, displayName: authManager.currentUser?.name, email: authManager.currentUser?.email)
                            },
                            onDelete: {
                                Task {
                                    await viewModel.removeQueueItem(item)
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.removeQueueItem(item)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(items.count * 80 + 20)) // Dynamic height based on items
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )

    }
}

private struct QueueRowView: View {
    let item: QueueItem
    let position: Int
    let onCallBack: () -> Void
    let onDelete: () -> Void
    private let deviceService = DeviceOrientationService.shared
    private var statusColor: Color { .orange }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: "person.fill.questionmark").foregroundColor(statusColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Priority")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("#\(position)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    Text(item.patientName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.clinic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.createdAt.asRelativeTimeString())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                // Call back button
                Button(action: onCallBack) {
                    Label("Call back", systemImage: "video.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(.vertical, deviceService.isIPad ? 16 : 10)
        .padding(.horizontal, deviceService.isIPad ? 20 : 12)
        .background(
            RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )

    }
}

// MARK: - Welcome Section
struct WelcomeSectionView: View {
    let user: User?
    private let deviceService = DeviceOrientationService.shared
    
    var body: some View {
        VStack(spacing: deviceService.isIPad ? 24 : 16) {
            HStack {
                VStack(alignment: .leading, spacing: deviceService.isIPad ? 12 : 8) {
                    Text("Welcome back!")
                        .font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(user?.name ?? "User")
                        .font(.system(size: deviceService.titleFontSize, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Image(systemName: "person.circle.fill")
                    .font(.system(size: deviceService.isIPad ? 80 : 60))
                    .foregroundColor(.blue)
            }
            
            if let email = user?.email {
                Text(email)
                    .font(.system(size: deviceService.bodyFontSize))
                    .foregroundColor(.secondary)
            }
        }
        .padding(deviceService.isIPad ? 32 : 20)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(deviceService.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: deviceService.isIPad ? 12 : 8, x: 0, y: 2)
    }
}

// MARK: - Recent Activity Section
struct RecentActivitySectionView: View {
    let activities: [ActivityItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                ForEach(activities) { activity in
                    ActivityRowView(activity: activity)
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Quick Action Card
struct QuickActionCardView: View {
    let action: QuickAction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundColor(action.color)
                
                VStack(spacing: 4) {
                    Text(action.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recent Calls Section
struct RecentCallsSectionView: View {
    let calls: [CallHistoryItem]
    let isLoading: Bool
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Calls")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button("See All") { selectedTab = 1 }
                    .font(.subheadline).foregroundColor(.blue)
            }.padding(.horizontal, 16).padding(.top, 16)

            if isLoading {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            // Skeleton for status icon
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                // Skeleton for patient name
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 140, height: 16)
                                
                                // Skeleton for call time
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 100, height: 12)
                            }
                            
                            Spacer()
                            
                            // Skeleton for status badge
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 70, height: 24)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 20)
            } else if recentApprovedRejectedCalls.isEmpty {
                EmptyStateView(
                    icon: "phone.circle",
                    title: "No Recent Calls",
                    subtitle: "Approved and rejected calls will appear here.",
                    iconSize: 60
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentApprovedRejectedCalls) { call in
                        RecentCallRowView(call: call)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var recentApprovedRejectedCalls: [CallHistoryItem] {
        calls.filter { call in
            // Show only approved or rejected calls (exclude queue/pending calls)
            let hasAcceptedAt = !(call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasRejectedAt = !(call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasAcceptedAt || hasRejectedAt
        }
        .sorted { call1, call2 in
            // Sort by most recent first
            return call1.calledAt > call2.calledAt
        }
        .prefix(5) // Limit to maximum 5 items
        .map { $0 } // Convert back to Array
    }
}

// MARK: - Recent Call Row (for approved/rejected calls)
struct RecentCallRowView: View {
    let call: CallHistoryItem
    
    private var callStatus: (text: String, color: Color, icon: String) {
        let hasAcceptedAt = !(call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasRejectedAt = !(call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        
        if hasRejectedAt {
            return ("Rejected", .red, "xmark.circle.fill")
        } else if hasAcceptedAt {
            return ("Approved", .green, "checkmark.circle.fill")
        } else {
            return ("Queue", .orange, "phone.fill")
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Leading glyph
            ZStack {
                Circle().fill(callStatus.color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: callStatus.icon).foregroundColor(callStatus.color)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(call.callerName).font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text(callStatus.text)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(callStatus.color.opacity(0.15))
                        .foregroundColor(callStatus.color)
                        .clipShape(Capsule())
                }
                
                if let scriptNumber = call.scriptNumber, !scriptNumber.isEmpty {
                    Text("#\(scriptNumber)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(call.calledFromClinic)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(call.calledAt.asRelativeTimeFromServer())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Pending Call Row (vertical)
struct PendingCallRowView: View {
    let call: CallHistoryItem
    
    private var statusColor: Color { .orange }
    
    var body: some View {
        HStack(spacing: 12) {
            // Leading glyph
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: "phone.fill").foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(call.callerName).font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text("Queue")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
                Text(call.calledFromClinic)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(call.calledAt.asRelativeTimeFromServer())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Removed local date helpers in favor of global extension in `AppCommon/Constants/AppConstants.swift`
}

// MARK: - Activity Row
struct ActivityRowView: View {
    let activity: ActivityItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.icon)
                .font(.title3)
                .foregroundColor(activity.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(activity.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(activity.timestamp)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}





#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(AuthManager())
} 
