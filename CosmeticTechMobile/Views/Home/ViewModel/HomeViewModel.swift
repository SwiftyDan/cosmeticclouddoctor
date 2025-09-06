//
//  HomeViewModel.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Quick Action Model
struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let actionType: QuickActionType
}

// MARK: - Quick Action Types
enum QuickActionType {
    case makeCall
    case callHistory
    case settings
    case support
}

// MARK: - Activity Item Model
struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let timestamp: String
}

// MARK: - Jitsi Parameters
struct JitsiParameters {
    let roomName: String
    let displayName: String?
    let email: String?
    let conferenceUrl: String?
    let roomId: String?
    let clinicSlug: String?
    let scriptId: Int?
    let scriptUUID: String?
    let clinicName: String?

    init(
        roomName: String,
        displayName: String?,
        email: String?,
        conferenceUrl: String?,
        roomId: String?,
        clinicSlug: String? = nil,
        scriptId: Int? = nil,
        scriptUUID: String? = nil,
        clinicName: String? = nil
    ) {
        self.roomName = roomName
        self.displayName = displayName
        self.email = email
        self.conferenceUrl = conferenceUrl
        self.roomId = roomId
        self.clinicSlug = clinicSlug
        self.scriptId = scriptId
        self.scriptUUID = scriptUUID
        self.clinicName = clinicName
    }
}

// MARK: - Home View Model Protocol
@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var quickActions: [QuickAction] { get }
    var recentActivities: [ActivityItem] { get }
    var callHistory: [CallHistoryItem] { get }
    var isLoadingCallHistory: Bool { get }
    var queueList: [QueueItem] { get }
    var jitsiParameters: JitsiParameters? { get }
    var isPresentingJitsi: Bool { get }
    func handleQuickAction(_ action: QuickAction)
    func refreshCallHistory() async
    func startVideoConsultation(conferenceURL: String, displayName: String?, email: String?)
}

// MARK: - Home View Model Implementation
@MainActor
class HomeViewModel: HomeViewModelProtocol {
    @Published var quickActions: [QuickAction] = []
    @Published var recentActivities: [ActivityItem] = []
    @Published var callHistory: [CallHistoryItem] = []
    @Published var isLoadingCallHistory: Bool = false
    @Published var callHistoryErrorMessage: String?

    // Real-time Queue
    @Published var queueList: [QueueItem] = [] {
        didSet {
            // Update badge count whenever queue list changes
            BadgeManager.shared.updateBadgeCount(to: queueList.count)
        }
    }
    @Published var isLoadingQueue: Bool = false

    @Published var jitsiParameters: JitsiParameters?
    @Published var isPresentingJitsi: Bool = false
    @Published var currentConsultationItem: QueueItem? = nil
    
    private let activityService: ActivityServiceProtocol
    private let callHistoryService: CallHistoryServiceProtocol
    private let queueAPIService: QueueAPIService = QueueAPIService()
    private let configurationService: ConfigurationServiceProtocol
    private let webSocketManager = WebSocketManager()
    @available(iOS 15.0, *)
    private var asyncClient: PusherAsyncWebSocketClient?
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        activityService: ActivityServiceProtocol = ActivityService(),
        callHistoryService: CallHistoryServiceProtocol = CallHistoryService(),
        configurationService: ConfigurationServiceProtocol = ConfigurationServiceFactory.createConfigurationService()
    ) {
        self.activityService = activityService
        self.callHistoryService = callHistoryService
        self.configurationService = configurationService
        setupQuickActions()
        loadRecentActivities()
        setupQueueRealtime()
        setupAsyncRealtimeIfAvailable()
        Task { [weak self] in
            await self?.loadInitialQueueFromAPI()
        }
        observeJitsiEvents()
        observeAppLifecycle()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        Task { @MainActor [weak webSocketManager] in
            webSocketManager?.disconnect()
        }
        if #available(iOS 15.0, *) {
            Task { [weak asyncClient] in
                await asyncClient?.disconnect(code: .goingAway)
            }
        }
    }
    
    private func setupQuickActions() {
        quickActions = [
            QuickAction(
                title: "Make Call",
                subtitle: "Start a new call",
                icon: "phone.fill",
                color: .green,
                actionType: .makeCall
            ),
            QuickAction(
                title: "Call History",
                subtitle: "View recent calls",
                icon: "clock.fill",
                color: .blue,
                actionType: .callHistory
            ),
            QuickAction(
                title: "Settings",
                subtitle: "App preferences",
                icon: "gear",
                color: .gray,
                actionType: .settings
            ),
            QuickAction(
                title: "Support",
                subtitle: "Get help",
                icon: "questionmark.circle.fill",
                color: .orange,
                actionType: .support
            )
        ]
    }
    
    private func loadRecentActivities() {
        recentActivities = activityService.getRecentActivities()
    }
    
    func handleQuickAction(_ action: QuickAction) {
        switch action.actionType {
        case .makeCall:
            break
        case .callHistory:
            break
        case .settings:
            break
        case .support:
            break
        }
    }
    
    // MARK: - Call History
    func refreshCallHistory() async {
        isLoadingCallHistory = true
        callHistoryErrorMessage = nil
        
        await callHistoryService.refreshCallHistory()
        callHistory = callHistoryService.getCallHistory()
        
        isLoadingCallHistory = false
    }

    // MARK: - Jitsi Helpers
    func startVideoConsultation(conferenceURL: String, displayName: String?, email: String?) {
        let roomName = extractPreferredRoomName(from: conferenceURL)
        let params = JitsiParameters(
            roomName: roomName,
            displayName: displayName,
            email: email,
            conferenceUrl: conferenceURL,
            roomId: conferenceURL
        )
        jitsiParameters = params
        isPresentingJitsi = true
    }
    
    /// Starts a consultation for a queue item
    /// This method tracks the consultation item and opens Jitsi
    /// Uses the same room setup logic as VoIP calls for consistency
    func startQueueConsultation(for item: QueueItem, displayName: String?, email: String?) {
        print("🎥 Starting consultation for queue item: \(item.patientName)")
        print("   - Script ID: \(item.scriptId?.description ?? "nil")")
        print("   - Script UUID: \(item.scriptUUID ?? "nil")")
        print("   - Clinic Slug: \(item.clinicSlug ?? "nil")")
        
        // Track the current consultation item
        currentConsultationItem = item
        
        // Use the same room setup logic as VoIP calls for consistency
        let roomName = resolveRoomNameForQueueItem(item)
        
        jitsiParameters = JitsiParameters(
            roomName: roomName,
            displayName: displayName,
            email: email,
            conferenceUrl: EnvironmentManager.shared.currentJitsiURL, // Same server as VoIP calls
            roomId: roomName,
            clinicSlug: item.clinicSlug,
            scriptId: item.scriptId
        )
        
        isPresentingJitsi = true
    }
    
    /// Resolves room name using the same logic as VoIP calls
    /// This ensures consistency between home screen call back and VoIP call answering
    private func resolveRoomNameForQueueItem(_ item: QueueItem) -> String {
        // Priority 1: Use explicit room_name if available
        if let roomName = item.roomName, !roomName.isEmpty {
            print("🎥 Using room_name from queue item: \(roomName)")
            return roomName
        }
        
        // Priority 2: Use script_uuid if available
        if let scriptUUID = item.scriptUUID, !scriptUUID.isEmpty {
            print("🎥 Using script_uuid from queue item: \(scriptUUID)")
            return scriptUUID
        }
        
        // Priority 3: Use script_id as fallback
        if let scriptId = item.scriptId {
            let fallback = "script_\(scriptId)"
            print("🎥 Using script_id as fallback room: \(fallback)")
            return fallback
        }
        
        // Priority 4: Generate a stable fallback
        let fallback = "cosmetic_\(Int(Date().timeIntervalSince1970))"
        print("⚠️ No room identifier found. Using fallback room: \(fallback)")
        return fallback
    }

    private func extractPreferredRoomName(from url: String) -> String {
        guard let comps = URLComponents(string: url) else { return "cosmetic_\(Int(Date().timeIntervalSince1970))" }
        let q = comps.queryItems ?? []
        if let roomName = q.first(where: { $0.name == "room_name" })?.value, !roomName.isEmpty { return roomName }
        if let roomId = q.first(where: { $0.name == "room_id" })?.value, !roomId.isEmpty { return roomId }
        if let room = q.first(where: { $0.name == "room" })?.value, !room.isEmpty { return room }
        if let scriptUUID = q.first(where: { $0.name == "script_uuid" })?.value, !scriptUUID.isEmpty { return scriptUUID }
        return "cosmetic_\(Int(Date().timeIntervalSince1970))"
    }
    
    // MARK: - Queue Realtime
    private func setupQueueRealtime() {
        // Bridge Starscream WebSocketManager → view model queue list
        webSocketManager.$queueItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.queueList = items
            }
            .store(in: &cancellables)
        
        // Connect to WebSocket for real-time updates
        webSocketManager.connect()
        
        // Setup notification handlers for queue updates
        setupQueueUpdateHandlers()
    }
    
    private func setupQueueUpdateHandlers() {
        // No longer needed since WebSocket manager handles queue updates locally
        // API is only called on initial load for first-time queue state
        print("📱 Queue update handlers: Using local WebSocket management for smooth transitions")
        print("   - No API calls on queue events for better performance")
        print("   - API only called once on initial app load")
    }

    private func setupAsyncRealtimeIfAvailable() {
        if #available(iOS 15.0, *) {
            // Configure URL for Reverb from configuration (production by default)
            let configService = ConfigurationServiceFactory.createConfigurationService()
            let host = configService.realtimeHost ?? "cosmeticcloud.tech"
            let port = configService.realtimePort ?? 443
            let appKey = configService.realtimeKey
            guard let url = URL(string: "wss://\(host):\(port)/app/\(appKey)") else { return }
            var cfg = RealtimeConfig(url: url)
            cfg.headers["Sec-WebSocket-Protocol"] = "pusher-channels-protocol-7"
            let client = PusherAsyncWebSocketClient(config: cfg)
            asyncClient = client
            // Stream events and map MobileQueueEvent similar to Starscream handler
            let task = Task { [weak self] in
                guard let self else { return }
                for await ev in client.events {
                    switch ev {
                    case .connected:
                        // subscribe to channel
                        let channelName = "mobile-queue.\(self.authUserId())"
                        let payload: [String: Any] = ["event": "pusher:subscribe", "data": ["channel": channelName]]
                        if let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) {
                            await client.send(text: text)
                        }
                    case .text(let text):
                        await self.handleAsyncText(text)
                    case .data(let d):
                        if let text = String(data: d, encoding: .utf8) { await self.handleAsyncText(text) }
                    case .disconnected, .error:
                        break
                    }
                }
            }
            // Store cancellation alongside Combine cancellables
            cancellables.insert(AnyCancellable { task.cancel() })
            Task { await client.connect() }
        }
    }

    private func loadInitialQueueFromAPI() async {
        isLoadingQueue = true
        do {
            let items = try await queueAPIService.fetchQueueEntries()
            // Simply set the queue items from API response
            webSocketManager.queueItems = items
        } catch {
            // silent fail: realtime will still populate
        }
        isLoadingQueue = false
    }

    // MARK: - Refresh Queue on Meeting End
    private func observeJitsiEvents() {
        NotificationCenter.default.addObserver(forName: .jitsiConferenceTerminated, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.refreshQueueFromAPI()
            }
        }
        
        // Handle Jitsi presentation from CallKit (like call back button)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("PresentJitsiFromCallKit"), object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            if let jitsiParameters = notification.userInfo?["jitsiParameters"] as? JitsiParameters {
                print("🎥 Received Jitsi presentation request from CallKit")
                self.jitsiParameters = jitsiParameters
                self.isPresentingJitsi = true
            }
        }
    }

    func refreshQueueFromAPI() async {
        isLoadingQueue = true
        do {
            let newItems = try await queueAPIService.fetchQueueEntries()
            
            print("🔄 API returned \(newItems.count) items, applying additional deduplication...")
            
            // Apply additional deduplication layer for safety
            let deduplicatedItems = deduplicateQueueItems(newItems)
            
            // Preserve original creation timestamps for existing items
            let updatedItems = deduplicatedItems.map { newItem in
                // Check if this item already exists in current queue
                if let existingItem = webSocketManager.queueItems.first(where: { $0.id == newItem.id }) {
                    // Preserve the original creation timestamp
                    return QueueItem(
                        id: newItem.id,
                        patientName: newItem.patientName,
                        clinic: newItem.clinic,
                        createdAt: existingItem.createdAt, // Keep original timestamp
                        clinicSlug: newItem.clinicSlug,
                        scriptId: newItem.scriptId,
                        scriptUUID: newItem.scriptUUID,
                        scriptNumber: newItem.scriptNumber,
                        roomName: newItem.roomName
                    )
                } else {
                    // New item, use the timestamp from API
                    return newItem
                }
            }
            
            // Update queue with preserved timestamps
            webSocketManager.queueItems = updatedItems
            print("🔄 Queue refreshed from API: \(updatedItems.count) items (timestamps preserved, duplicates removed)")
        } catch {
            print("❌ Failed to refresh queue from API: \(error)")
        }
        isLoadingQueue = false
    }
    
        /// Removes a queue item via API call
    func removeQueueItem(_ item: QueueItem) async {
        print("🗑️ Queue item removal requested:")
        print("   - Script ID: \(item.scriptId?.description ?? "nil")")
        print("   - Script UUID: \(item.scriptUUID ?? "nil")")
        print("   - Script Number: \(item.scriptNumber ?? "nil")")
        print("   - Patient Name: \(item.patientName)")
        print("   - Clinic: \(item.clinic)")
        
        // Check if we have the required fields for deletion
        guard let scriptId = item.scriptId,
              let clinicSlug = item.clinicSlug else {
            print("❌ Cannot remove queue item: missing required fields")
            print("   - Script ID: \(item.scriptId?.description ?? "nil")")
            print("   - Clinic Slug: \(item.clinicSlug ?? "nil")")
            return
        }

        // Use scriptUUID if available, otherwise use scriptNumber as fallback
        let scriptUUID = item.scriptUUID ?? item.scriptNumber ?? item.id

        guard !scriptUUID.isEmpty else {
            print("❌ Cannot remove queue item: no valid identifier available")
            print("   - Script ID: \(scriptId)")
            print("   - Script UUID: \(item.scriptUUID ?? "nil")")
            print("   - Script Number: \(item.scriptNumber ?? "nil")")
            print("   - Item ID: \(item.id)")
            return
        }

        print("🗑️ Attempting to remove queue item via API:")
        print("   - Script ID: \(scriptId)")
        print("   - Script UUID: \(scriptUUID)")
        print("   - Clinic Slug: \(clinicSlug)")
        print("   - Patient Name: \(item.patientName)")
        print("   - Clinic: \(item.clinic)")

        do {
            let success = try await queueAPIService.removeQueueItem(
                scriptUUID: scriptUUID,
                scriptId: scriptId,
                clinicSlug: clinicSlug,
                clinicName: item.clinic,
                callerName: item.patientName,
                roomName: item.roomName
            )

            if success {
                print("✅ Queue item removed successfully via API")
                // Refresh queue to get updated state
                await refreshQueueFromAPI()
            } else {
                print("❌ Failed to remove queue item: API returned false")
            }
        } catch {
            print("❌ Failed to remove queue item: \(error)")
        }
    }


    private func handleAsyncText(_ message: String) async {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }
        switch event {
        case "pusher:connection_established":
            break
        case "pusher_internal:subscription_succeeded":
            break
        case "pusher_internal:subscription_error":
            break
        case "MobileQueueEvent":
            if let dataString = json["data"] as? String,
               let nested = dataString.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: nested)) as? [String: Any] {
                await applyQueueEvent(dict)
            } else if let dict = json["data"] as? [String: Any] {
                await applyQueueEvent(dict)
            }
        default:
            break
        }
    }

    private func applyQueueEvent(_ eventData: [String: Any]) async {
        // Handle MobileQueueEvent from async WebSocket client
        let eventType = eventData["action"] as? String ?? "update"
        let scriptUUID = eventData["script_uuid"] as? String ?? "unknown"
        // Handle both string and integer script_id types from WebSocket
        let scriptId: Int? = {
            if let intValue = eventData["script_id"] as? Int {
                return intValue
            } else if let stringValue = eventData["script_id"] as? String, let intValue = Int(stringValue) {
                return intValue
            }
            return nil
        }()
        
        print("🔄 Async queue event received: \(eventType) for script_uuid: \(scriptUUID), script_id: \(scriptId?.description ?? "nil")")
        
        // For all WebSocket events, trigger API refresh to maintain consistency
        // This follows the Android API approach where the backend is the source of truth
        Task { @MainActor in
            await self.refreshQueueFromAPI()
                }
    }
    
    /// Additional deduplication layer for queue items
    /// This provides a safety net in case the API-level deduplication misses anything
    private func deduplicateQueueItems(_ items: [QueueItem]) -> [QueueItem] {
        print("🔍 HomeViewModel: Additional deduplication layer for \(items.count) items")
        
        var seenIdentifiers: Set<String> = []
        var seenScriptUUIDs: Set<String> = []
        var seenScriptIds: Set<Int> = []
        var deduplicated: [QueueItem] = []
        var duplicatesFound = 0
        
        for item in items {
            var isDuplicate = false
            var duplicateReason = ""
            
            // Check by scriptUUID first (most reliable identifier)
            if let scriptUUID = item.scriptUUID, !scriptUUID.isEmpty {
                if seenScriptUUIDs.contains(scriptUUID) {
                    isDuplicate = true
                    duplicateReason = "scriptUUID: \(scriptUUID)"
                } else {
                    seenScriptUUIDs.insert(scriptUUID)
                }
            }
            
            // Check by scriptId if no scriptUUID or not duplicate
            if !isDuplicate, let scriptId = item.scriptId, scriptId > 0 {
                if seenScriptIds.contains(scriptId) {
                    isDuplicate = true
                    duplicateReason = "scriptId: \(scriptId)"
                } else {
                    seenScriptIds.insert(scriptId)
                }
            }
            
            // Check by mapped ID as fallback
            if !isDuplicate {
                if seenIdentifiers.contains(item.id) {
                    isDuplicate = true
                    duplicateReason = "mapped ID: \(item.id)"
                } else {
                    seenIdentifiers.insert(item.id)
                }
            }
            
            if isDuplicate {
                duplicatesFound += 1
                print("🚫 HomeViewModel: Duplicate detected and removed:")
                print("   - Patient: \(item.patientName)")
                print("   - Clinic: \(item.clinic)")
                print("   - Script UUID: \(item.scriptUUID ?? "nil")")
                print("   - Script ID: \(item.scriptId?.description ?? "nil")")
                print("   - Mapped ID: \(item.id)")
                print("   - Reason: \(duplicateReason)")
            } else {
                deduplicated.append(item)
            }
        }
        
        print("🎯 HomeViewModel deduplication completed:")
        print("   - Original items: \(items.count)")
        print("   - Duplicates found: \(duplicatesFound)")
        print("   - Final unique items: \(deduplicated.count)")
        
        return deduplicated
    }
    
    /// Handles consultation ending and automatically removes the queue item
    /// This is called when Jitsi meetings end (either manually or automatically)
    func handleConsultationEnded() {
        guard let consultationItem = currentConsultationItem else {
            print("🎥 No consultation item to remove")
            return
        }
        
        print("🎥 Consultation ended, automatically removing queue item: \(consultationItem.patientName)")
        print("   - Script ID: \(consultationItem.scriptId?.description ?? "nil")")
        print("   - Script UUID: \(consultationItem.scriptUUID ?? "nil")")
        print("   - Clinic Slug: \(consultationItem.clinicSlug ?? "nil")")
        
        // Clear the current consultation item
        currentConsultationItem = nil
        
        // Automatically remove the item from the queue using the same API endpoint
        Task {
            await removeQueueItem(consultationItem)
        }
    }
    
    /// Cleans up consultation state when Jitsi view is dismissed
    /// This ensures proper cleanup even if the view is dismissed without ending the call
    func cleanupConsultation() {
        if currentConsultationItem != nil {
            print("🎥 Jitsi view dismissed, cleaning up consultation state")
            currentConsultationItem = nil
        }
    }
    
    private func authUserId() -> String {
        let keychain = KeychainService()
        if let user: User = keychain.retrieve(key: "user_data", type: User.self) {
            return String(user.userId)
        }
        return "0"
    }
    
    /// Observes app lifecycle events to manage badge count
    private func observeAppLifecycle() {
        // Clear badge when app becomes active (user opens the app)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 HomeViewModel: App became active, updating badge count to match queue")
            // Update badge to match current queue count
            BadgeManager.shared.updateBadgeCount(to: self?.queueList.count ?? 0)
        }
        
        // Update badge when app enters background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 HomeViewModel: App entered background, ensuring badge reflects queue count")
            // Ensure badge reflects current queue count when going to background
            BadgeManager.shared.updateBadgeCount(to: self?.queueList.count ?? 0)
        }
    }
} 