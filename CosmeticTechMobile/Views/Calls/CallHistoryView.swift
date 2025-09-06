//
//  CallHistoryView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI
import SkeletonView

struct CallHistoryView: View {
    @ObservedObject var callHistoryService: CallHistoryService
    @Environment(\.dismiss) private var dismiss
    private let deviceService = DeviceOrientationService.shared
    @State private var searchText = ""
    @State private var selectedStatus: String? = nil
    @State private var showingClearConfirmation = false
    @StateObject private var viewModel = CallsViewModel()
    
    private var filteredCalls: [CallHistoryItem] {
        var calls = callHistoryService.getCallHistory()
        
        if !searchText.isEmpty {
            calls = calls.filter { call in
                call.callerName.localizedCaseInsensitiveContains(searchText) ||
                call.calledFromClinic.localizedCaseInsensitiveContains(searchText) ||
                String(call.id).localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let status = selectedStatus {
            calls = calls.filter { call in
                switch status {
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                searchAndFilterBar
                
                // Call List
                if callHistoryService.isLoading {
                    loadingView
                } else if filteredCalls.isEmpty {
                    emptyStateView
                } else {
                    callListView
                }
            }
            .navigationTitle("Call History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await callHistoryService.testAPIConnection() }
                        }) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            Task { await callHistoryService.refreshCallHistory() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(callHistoryService.isLoading)
                    }
                }
            }
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
                            } else {
                                EmptyView()
                            }
                        }
                    },
                    label: { EmptyView() }
                )
                .hidden()
            )
        }
        .onAppear { Task { await callHistoryService.refreshCallHistory() } }
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
                    onEndCall: { [weak viewModel] in
                        // End the call and dismiss the view
                        print("🎥 Call ended from CallHistoryView, dismissing view")
                        viewModel?.endCall()
                    }
                )
            }
        }
        .alert("Error", isPresented: .constant(callHistoryService.errorMessage != nil)) {
            Button("OK") { callHistoryService.errorMessage = nil }
        } message: {
            if let errorMessage = callHistoryService.errorMessage { Text(errorMessage) }
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack {
            ProgressView().scaleEffect(1.2)
            Text("Loading call history...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Search and Filter Bar
    private var searchAndFilterBar: some View {
        VStack(spacing: deviceService.isIPad ? 16 : 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search calls...", text: $searchText).textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button("Clear") { searchText = "" }.foregroundColor(.blue)
                }
            }
            .padding(.horizontal, deviceService.isIPad ? 24 : 16)
            .padding(.vertical, deviceService.isIPad ? 16 : 12)
            .background(Color(uiColor: .systemGray6))
            .cornerRadius(deviceService.cornerRadius)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: deviceService.isIPad ? 16 : 12) {
                    FilterPill(title: "All", isSelected: selectedStatus == nil) { selectedStatus = nil }
                    FilterPill(title: "Approved", isSelected: selectedStatus == "approved") { selectedStatus = "approved" }
                    FilterPill(title: "Rejected", isSelected: selectedStatus == "rejected") { selectedStatus = "rejected" }
                    FilterPill(title: "Queue", isSelected: selectedStatus == "queue") { selectedStatus = "queue" }
                }
                .padding(.horizontal, deviceService.isIPad ? 32 : 20)
            }
        }
        .padding(.horizontal, deviceService.horizontalPadding)
        .padding(.vertical, deviceService.isIPad ? 24 : 16)
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Call List View
    private var callListView: some View {
        List(filteredCalls) { call in
            CallHistoryCompactRowView(
                call: call,
                onTap: { viewModel.select(call: call) },
                onCallBack: { },
                showCallBackButton: false
            )
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: deviceService.isIPad ? 32 : 20) {
            Image(systemName: "phone.down").font(.system(size: deviceService.isIPad ? 80 : 60)).foregroundColor(.secondary)
            VStack(spacing: deviceService.isIPad ? 12 : 8) {
                Text("No Call History").font(.system(size: deviceService.headlineFontSize, weight: .semibold)).foregroundColor(.primary)
                Text("Your call history will appear here once you make or receive calls.")
                    .font(.system(size: deviceService.bodyFontSize)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button("Refresh") { Task { await callHistoryService.refreshCallHistory() } }.foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(deviceService.isIPad ? 40 : 20)
    }
}



// Removed inline CallDetailsView and ConsultationField to keep modularization per SOLID.

#Preview {
    CallHistoryView(callHistoryService: CallHistoryService())
} 