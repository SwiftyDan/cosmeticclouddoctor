//
//  CallsView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI

struct CallsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var callHistoryService = CallHistoryService()
    @StateObject private var viewModel = CallsViewModel()
    private let deviceService = DeviceOrientationService.shared
    @State private var searchText = ""
    @State private var selectedStatus: String? = nil
    
    // Check if we're on a tablet for layout decisions
    private var isTablet: Bool {
        deviceService.isIPad
    }
    
    var body: some View {
        NavigationView {
            if isTablet {
                // Tablet Layout: Side-by-side view
                HStack(spacing: 0) {
                    // Left Panel: Call List
                    VStack(spacing: 0) {
                        // Search and Filter Section
                        VStack(spacing: 24) {
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search calls...", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                
                                if !searchText.isEmpty {
                                    Button("Clear") { searchText = "" }
                                        .font(.system(size: deviceService.captionFontSize))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(20)
                            .background(Color(.systemBackground))
                            .cornerRadius(deviceService.cornerRadius)
                            
                            // Filter Pills
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    FilterPill(title: "All", isSelected: selectedStatus == nil) { selectedStatus = nil }
                                    FilterPill(title: "Approved", isSelected: selectedStatus == "approved") { selectedStatus = "approved" }
                                    FilterPill(title: "Rejected", isSelected: selectedStatus == "rejected") { selectedStatus = "rejected" }
                                    FilterPill(title: "Queue", isSelected: selectedStatus == "queue") { selectedStatus = "queue" }
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                        
                        // Call History List
                        if callHistoryService.isLoading {
                            // Simple skeleton view without animation
                            CallHistorySkeletonView()
                        } else if filteredCalls.isEmpty {
                            EmptyStateView(
                                icon: "phone.circle",
                                title: "No Calls Found",
                                subtitle: "Try adjusting your search or filters"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(groupedCalls.keys.sorted().reversed(), id: \.self) { date in
                                        if let calls = groupedCalls[date] {
                                            // Date Header
                                            HStack {
                                                Text(date)
                                                    .font(.headline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGroupedBackground))
                                            
                                            // Calls for this date
                                            VStack(spacing: 0) {
                                                ForEach(calls) { call in
                                                    CallHistoryCompactRowView(
                                                        call: call,
                                                        onTap: { viewModel.select(call: call) },
                                                        onCallBack: { },
                                                        showCallBackButton: false
                                                    )
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 10)
                                                    .background(Color(.systemBackground))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(viewModel.selectedCall?.id == call.id ? Color.blue : Color.clear, lineWidth: 2)
                                                    )
                                                    
                                                    if call.id != calls.last?.id {
                                                        Divider().padding(.leading, 20)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.bottom, 100)
                            }
                        }
                                         }
                     .frame(width: 400)
                     .background(Color(.systemGroupedBackground))
                     
                     // Divider between panels
                     Divider()
                         .background(Color(.separator))
                    
                                         // Right Panel: Call Details or Empty State
                     VStack {
                         if let selectedCall = viewModel.selectedCall {
                             CallDetailsView(call: selectedCall)
                         } else {
                             // Empty state when no call is selected
                             VStack(spacing: 24) {
                                 Image(systemName: "phone.circle")
                                     .font(.system(size: 80))
                                     .foregroundColor(.secondary)
                                     .opacity(0.7)
                                 
                                 Text("Select a Call")
                                     .font(.title2)
                                     .fontWeight(.semibold)
                                     .foregroundColor(.primary)
                                 
                                 Text("Choose a call from the list to view its details")
                                     .font(.body)
                                     .foregroundColor(.secondary)
                                     .multilineTextAlignment(.center)
                                     .padding(.horizontal, 40)
                                 
                                 // Add a subtle hint
                                 Text("Tap any call in the list to get started")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                                     .padding(.top, 8)
                             }
                             .frame(maxWidth: .infinity, maxHeight: .infinity)
                             .background(Color(.systemBackground))
                             .transition(.opacity.combined(with: .scale))
                         }
                     }
                     .frame(maxWidth: .infinity)
                     .animation(.easeInOut(duration: 0.3), value: viewModel.selectedCall != nil)
                }
                .navigationTitle("Call History")
                .navigationBarTitleDisplayMode(.large)
            } else {
                // Phone Layout: Original implementation
                ZStack {
                    // Background
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                    
                    // Content
                    VStack(spacing: 0) {
                        // Search and Filter Section
                        VStack(spacing: 16) {
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search calls...", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                
                                if !searchText.isEmpty {
                                    Button("Clear") { searchText = "" }
                                        .font(.system(size: deviceService.captionFontSize))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(deviceService.cornerRadius)
                            
                            // Filter Pills
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    FilterPill(title: "All", isSelected: selectedStatus == nil) { selectedStatus = nil }
                                    FilterPill(title: "Approved", isSelected: selectedStatus == "approved") { selectedStatus = "approved" }
                                    FilterPill(title: "Rejected", isSelected: selectedStatus == "rejected") { selectedStatus = "rejected" }
                                    FilterPill(title: "Queue", isSelected: selectedStatus == "queue") { selectedStatus = "queue" }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.horizontal, deviceService.horizontalPadding)
                        .padding(.top, 20)
                        
                        // Call History List
                        if callHistoryService.isLoading {
                            // Simple skeleton view without animation
                            CallHistorySkeletonView()
                        } else if filteredCalls.isEmpty {
                            EmptyStateView(
                                icon: "phone.circle",
                                title: "No Calls Found",
                                subtitle: "Try adjusting your search or filters"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(groupedCalls.keys.sorted().reversed(), id: \.self) { date in
                                        if let calls = groupedCalls[date] {
                                            // Date Header
                                            HStack {
                                                Text(date)
                                                    .font(.headline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGroupedBackground))
                                            
                                            // Calls for this date
                                            VStack(spacing: 0) {
                                                ForEach(calls) { call in
                                                    CallHistoryCompactRowView(
                                                        call: call,
                                                        onTap: { viewModel.select(call: call) },
                                                        onCallBack: { },
                                                        showCallBackButton: false
                                                    )
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 10)
                                                    .background(Color(.systemBackground))
                                                    
                                                    if call.id != calls.last?.id {
                                                        Divider().padding(.leading, 20)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.bottom, 100)
                            }
                        }
                    }
                }
                .navigationTitle("Call History")
                .navigationBarTitleDisplayMode(.large)
                .background(
                    NavigationLink(
                        isActive: Binding(
                            get: { viewModel.selectedCall != nil },
                            set: { newValue in if !newValue { viewModel.selectedCall = nil } }
                        ),
                        destination: {
                            Group {
                                if let call = viewModel.selectedCall {
                                    CallDetailsView(call: call)
                                } else { EmptyView() }
                            }
                        },
                        label: { EmptyView() }
                    ).hidden()
                )
            }
        }
        .onAppear { 
            Task { await callHistoryService.refreshCallHistory() }
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
                    scriptUUID: params.scriptUUID,
                    clinicName: params.clinicName,
                    onEndCall: { [weak viewModel] in
                        // End the call and dismiss the view
                        print("🎥 Call ended from CallsView, dismissing view")
                        viewModel?.endCall()
                    }
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    private var filteredCalls: [CallHistoryItem] {
        var calls = callHistoryService.callHistory
        
        if !searchText.isEmpty {
            calls = calls.filter { call in
                call.callerName.localizedCaseInsensitiveContains(searchText) ||
                call.calledFromClinic.localizedCaseInsensitiveContains(searchText) ||
                String(call.id).localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let selectedStatus = selectedStatus {
            calls = calls.filter { call in
                switch selectedStatus {
                case "approved":
                    // Show calls where acceptedAt has a value
                    return !(call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                case "rejected":
                    // Show calls where rejectedAt has a value
                    return !(call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                case "queue":
                    // Show calls where both acceptedAt and rejectedAt are empty/nil
                    let acceptedEmpty = call.acceptedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                    let rejectedEmpty = call.rejectedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                    return acceptedEmpty && rejectedEmpty
                default:
                    return true
                }
            }
        }
        
        return calls
    }
    
    private var groupedCalls: [String: [CallHistoryItem]] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .full
        
        return Dictionary(grouping: filteredCalls) { call in
            if let date = dateFormatter.date(from: call.calledAt) {
                return displayFormatter.string(from: date)
            }
            return "Unknown Date"
        }
    }
    
    // Derived status no longer used for filtering; kept for potential future logic
    private func derivedStatus(for call: CallHistoryItem) -> String {
        if call.rejectedAt != nil { return "rejected" }
        if call.acceptedAt != nil { return "approved" }
        return "queue"
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(uiColor: .systemGray6))
                .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Call History Skeleton View
struct CallHistorySkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    // Date Header Skeleton
                    HStack {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 20)
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(.systemGroupedBackground))
                    
                    // Call Row Skeleton
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { callIndex in
                            HStack(spacing: 12) {
                                // Avatar skeleton
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 40, height: 40)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    // Name skeleton
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 150, height: 16)
                                        .cornerRadius(4)
                                    
                                    // Status skeleton
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 80, height: 14)
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                
                                // Time skeleton
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 14)
                                    .cornerRadius(4)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground))
                            
                            if callIndex < 2 {
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                    
                    if index < 7 {
                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }
}

#Preview {
    CallsView()
        .environmentObject(AuthManager())
} 