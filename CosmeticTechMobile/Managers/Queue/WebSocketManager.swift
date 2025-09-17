import Foundation
import Combine
import Starscream
import UIKit

@MainActor
final class WebSocketManager: ObservableObject, WebSocketDelegate {
    // MARK: - Published UI State
    @Published var queueItems: [QueueItem] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastMessage: String = ""

    // MARK: - Internal State
    private var socket: WebSocket?
    private var isConnected = false
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var uuidSubscribeRetryTask: Task<Void, Never>?
    private var pingTimer: Timer?
    private var cleanupTimer: Timer?
    private let maxReconnectDelay: TimeInterval = 30

    // MARK: - Local notification de-duplication (avoid double alerts for the same item)
    private var notifiedAddIds: Set<String> = []
    private var notifiedRemoveIds: Set<String> = []
    private var lastUpdateEventSignature: String = ""

    // MARK: - Current Authenticated User Id (use user_id instead of doctor_user_id)
    private var currentUserId: Int {
        let keychain = KeychainService()
        if let user: User = keychain.retrieve(key: "user_data", type: User.self) {
            return user.userId
        }
        return 0
    }
    private var currentUserUUID: String {
        let keychain = KeychainService()
        if let uuid: String = keychain.retrieve(key: "user_uuid", type: String.self) {
            return uuid
        }
        return ""
    }
    private let baseURL = EnvironmentManager.shared.currentSocketURL
    private let reverbKey = ConfigurationServiceFactory.createConfigurationService().realtimeKey
    private let reverbHost = EnvironmentManager.shared.currentSocketURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    private let reverbPort = 443

    enum ConnectionStatus {
        case connected
        case disconnected
        case connecting
        case error(String)
    }

    init() {
        setupWebSocket()
    }

    // MARK: - Setup
    private func setupWebSocket() {
        let wsURL = "wss://\(reverbHost):\(reverbPort)/app/\(reverbKey)"
        
        guard let url = URL(string: wsURL) else {
            print("Invalid WebSocket URL: \(wsURL)")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Required by Reverb/Pusher Channels
        request.setValue("pusher-channels-protocol-7", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let ws = WebSocket(request: request)
        
        ws.delegate = self
        ws.respondToPingWithPong = true
        socket = ws
    }

    // MARK: - Lifecycle
    func connect() {
        shouldReconnect = true
        if socket == nil { setupWebSocket() }
        guard let socket else { return }
        connectionStatus = .connecting
        
        socket.connect()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.disconnect()
        connectionStatus = .disconnected
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        socket = nil
    }

    deinit {
        // Hop to the main actor to satisfy isolation for cleanup
        Task { @MainActor [weak self] in
            self?.disconnect()
        }
    }

    // MARK: - WebSocketDelegate
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            #if DEBUG
            print("WS connected: headers=\(headers)")
            #endif
            
            connectionStatus = .connected
            isConnected = true
            reconnectAttempts = 0
            startPing()
            ensureSubscribeWithUUID()
            
            // Clean up any duplicates that might have accumulated
            cleanupDuplicates()

        case .disconnected(let reason, let code):
            
            connectionStatus = .disconnected
            isConnected = false
            stopTimers()
            scheduleReconnect()

        case .text(let string):
            print("WS received text: \(string)")
            handleMessage(string)

        case .binary(let data):
            break

        case .error(let error):
            
            connectionStatus = .error(error?.localizedDescription ?? "Unknown error")
            isConnected = false
            stopTimers()
            scheduleReconnect()

        case .cancelled:
            
            connectionStatus = .disconnected
            isConnected = false
            stopTimers()
            scheduleReconnect()

        case .ping(_):
            break

        case .pong(_):
            break

        case .viabilityChanged(let isViable):
            break

        case .reconnectSuggested(let shouldReconnect):
            
            if shouldReconnect && !isConnected {
                connect()
            }

        case .peerClosed:
            
            connectionStatus = .disconnected
            isConnected = false
            stopTimers()
            scheduleReconnect()
        }
    }

    // MARK: - Subscribe
    private func subscribeToChannel() {
        let uuidSuffix = currentUserUUID.isEmpty ? "" : ".\(currentUserUUID)"
        let channelName = "mobile-queue.\(currentUserId)\(uuidSuffix)"
        let subscribeMessage: [String: Any] = [
            "event": "pusher:subscribe",
            "data": ["channel": channelName]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: subscribeMessage),
           let jsonString = String(data: data, encoding: .utf8) {
            #if DEBUG
            print("WS subscribing to: \(channelName)")
            #endif
            
            socket?.write(string: jsonString)
        }
    }

    private func ensureSubscribeWithUUID() {
        // If UUID already available, subscribe immediately
        let hasUUID = !currentUserUUID.isEmpty
        if hasUUID {
            subscribeToChannel()
            return
        }
        // Retry for a short window to allow login to persist UUID before subscribing
        uuidSubscribeRetryTask?.cancel()
        uuidSubscribeRetryTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<10 { // retry up to ~10 seconds
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !self.currentUserUUID.isEmpty {
                    self.subscribeToChannel()
                    return
                }
            }
            // Fallback: subscribe with user_id only if UUID never arrives
            self.subscribeToChannel()
        }
    }

    // MARK: - Message Handling
    private func handleMessage(_ message: String) {
        lastMessage = message
        guard let data = message.data(using: .utf8) else {
            
            return
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let event = json["event"] as? String {
                    switch event {
                    case "pusher:connection_established":
                        break
                    case "pusher_internal:subscription_succeeded":
                        #if DEBUG
                        print("WS subscription succeeded")
                        #endif
                        break
                    case "pusher_internal:subscription_error":
                        break
                    case "MobileQueueEvent":
                        handleMobileQueueEventContainer(json)
                    default:
                        break
                    }
                }
            }
        } catch {
            // Swallow JSON parse errors silently
        }
    }

    // The event data for Pusher-compatible servers is typically nested as a JSON string under "data"
    private func handleMobileQueueEventContainer(_ container: [String: Any]) {
        if let dataString = container["data"] as? String,
           let nested = dataString.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: nested)) as? [String: Any] {
            handleMobileQueueEvent(dict)
            return
        }
        if let dict = container["data"] as? [String: Any] {
            handleMobileQueueEvent(dict)
        }
    }

    private func handleMobileQueueEvent(_ eventData: [String: Any]) {
        // Respect doctor_user_id targeting; ignore events for other users
        let doctorIdFromEvent: Int? = (eventData["doctor_user_id"] as? Int) ?? Int((eventData["doctor_user_id"] as? String) ?? "")
        if let targetDoctorId = doctorIdFromEvent, targetDoctorId != currentUserId { 
            print("⚠️ Ignoring event for different doctor: \(targetDoctorId) vs current: \(currentUserId)")
            return 
        }
        
        let action = (eventData["action"] as? String)?.lowercased() ?? "update"
        
        switch action {
        case "remove":
            handleRemoveEvent(eventData: eventData)
        case "add":
            handleAddEvent(eventData: eventData)
        case "update":
            handleUpdateEvent(eventData: eventData)
        default:
            print("⚠️ Unknown action type: \(action)")
        }
    }
    
    private func handleRemoveEvent(eventData: [String: Any]) {
        print("🔍 Raw remove event data: \(eventData)")
        
        let scriptUUID: String? = (eventData["script_uuid"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        // Handle both string and integer script_id types from WebSocket
        let scriptId: Int? = {
            if let intValue = eventData["script_id"] as? Int {
                return intValue > 0 ? intValue : nil
            } else if let stringValue = eventData["script_id"] as? String, let intValue = Int(stringValue) {
                return intValue > 0 ? intValue : nil
            }
            return nil
        }()
        
        print("🗑️ Queue removal event received for script_uuid: \(scriptUUID ?? "nil"), script_id: \(scriptId?.description ?? "nil")")
        print("   - Current queue items: \(queueItems.count)")
        print("   - Looking for items with:")
        print("     * scriptUUID: \(scriptUUID ?? "nil")")
        print("     * scriptId: \(scriptId?.description ?? "nil")")
        
        // Debug current queue state
        debugQueueState()
        
        // Use the helper method to find the item
        if let foundItem = findItemInQueue(scriptUUID: scriptUUID, scriptId: scriptId) {
            print("     ✓ Found item to remove: \(foundItem.patientName)")
            print("        - ID: \(foundItem.id)")
            print("        - Script ID: \(foundItem.scriptId?.description ?? "nil")")
            print("        - Script UUID: \(foundItem.scriptUUID ?? "nil")")
            
            // Remove the found item
            queueItems.removeAll { item in
                item.id == foundItem.id
            }
            
            print("✅ Local queue updated - item removed successfully")
            
            // Show push notification for queue removal
            NotificationService.shared.scheduleQueueRemovedNotification(
                patientName: foundItem.patientName,
                id: foundItem.id
            )
            
            // Check if there's an active VoIP call with matching script_id and terminate it
            handleQueueRemovalWithBackgroundSupport(scriptId: scriptId, scriptUUID: scriptUUID, patientName: foundItem.patientName)
            
            return
        }
        
        // If we get here, the item wasn't found in queue, but still check if we should end current call
        print("⚠️ Item not found in queue - checking if current call should be ended")
        
        // Show notification even if item wasn't found in local queue (in case it was already removed)
        // This ensures the user gets notified about the cancellation regardless of local state
        NotificationService.shared.scheduleQueueRemovedNotification(
            patientName: nil,
            id: scriptUUID ?? "\(scriptId ?? 0)"
        )
        
        // Check if there's an active VoIP call with matching script_id and terminate it
        handleQueueRemovalWithBackgroundSupport(scriptId: scriptId, scriptUUID: scriptUUID, patientName: nil)
    }
    
    private func handleAddEvent(eventData: [String: Any]) {
        print("➕ Queue addition event received")
        print("   - Adding to local queue immediately for smooth transition")
        
        // Create QueueItem from event data
        guard let newItem = QueueItem.fromBroadcastPayload(eventData) else {
            print("❌ Failed to create QueueItem from event data")
            return
        }
        
        // Enhanced duplicate detection with detailed logging
        let (isDuplicate, duplicateReason) = checkForDuplicates(newItem: newItem, existingItems: queueItems)
        
        if isDuplicate {
            print("⚠️ Duplicate queue item detected - skipping: \(newItem.patientName)")
            print("   - Script UUID: \(newItem.scriptUUID ?? "nil")")
            print("   - Script ID: \(newItem.scriptId?.description ?? "nil")")
            print("   - Mapped ID: \(newItem.id)")
            print("   - Duplicate reason: \(duplicateReason)")
            return
        }
        
        // Add to local queue if not duplicate
        queueItems.append(newItem)
        print("✅ Local queue updated - item added successfully: \(newItem.patientName)")
        print("   - Total items in queue: \(queueItems.count)")
    }
    
    private func handleUpdateEvent(eventData: [String: Any]) {
        print("🔄 Queue update event received")
        
        // Check if this is a duplicate update event by comparing with last update
        let eventSignature = createEventSignature(eventData)
        if eventSignature == lastUpdateEventSignature {
            print("⚠️ Duplicate update event detected - skipping")
            return
        }
        
        // Store the event signature to prevent duplicates
        lastUpdateEventSignature = eventSignature
        
        // Post notification for ViewModel to handle - no local queue manipulation
        // This follows the Android API approach where the backend is the source of truth
        NotificationCenter.default.post(name: Notification.Name("QueueItemUpdatedEvent"), object: nil, userInfo: eventData)
        
        print("✅ Update event processed - triggering API refresh to maintain consistency with backend")
    }
    
    // Helper method to create a unique signature for events to prevent duplicates
    private func createEventSignature(_ eventData: [String: Any]) -> String {
        let scriptUUID = eventData["script_uuid"] as? String ?? ""
        // Handle both string and integer script_id types from WebSocket
        let scriptId: Int = {
            if let intValue = eventData["script_id"] as? Int {
                return intValue
            } else if let stringValue = eventData["script_id"] as? String, let intValue = Int(stringValue) {
                return intValue
            }
            return 0
        }()
        let timestamp = eventData["timestamp"] as? Int ?? 0
        let action = eventData["action"] as? String ?? ""
        
                return "\(action)_\(scriptUUID)_\(scriptId)_\(timestamp)"
    }
    
    /// Enhanced duplicate detection for queue items
    /// Returns (isDuplicate, reason) tuple for detailed logging
    private func checkForDuplicates(newItem: QueueItem, existingItems: [QueueItem]) -> (Bool, String) {
        for existingItem in existingItems {
            // Check by scriptUUID first (most reliable identifier)
            if let newScriptUUID = newItem.scriptUUID, 
               let existingScriptUUID = existingItem.scriptUUID,
               !newScriptUUID.isEmpty, !existingScriptUUID.isEmpty,
               newScriptUUID == existingScriptUUID {
                return (true, "scriptUUID match: \(newScriptUUID)")
            }
            
            // Check by scriptId
            if let newScriptId = newItem.scriptId, 
               let existingScriptId = existingItem.scriptId,
               newScriptId > 0, existingScriptId > 0,
               newScriptId == existingScriptId {
                return (true, "scriptId match: \(newScriptId)")
            }
            
            // Check by mapped ID
            if newItem.id == existingItem.id {
                return (true, "mapped ID match: \(newItem.id)")
            }
        }
        
        return (false, "no duplicates found")
    }
    
    /// Helper method to find items in the queue by various identifiers
    /// This provides flexible matching for WebSocket events
    private func findItemInQueue(scriptUUID: String?, scriptId: Int?) -> QueueItem? {
        guard let scriptUUID = scriptUUID, !scriptUUID.isEmpty else {
            // If no scriptUUID, try to find by scriptId
            guard let scriptId = scriptId else { return nil }
            
            return queueItems.first { item in
                // Direct scriptId match
                if item.scriptId == scriptId { return true }
                // ID contains script_id
                if item.id.contains("script_\(scriptId)") { return true }
                // ID contains just the number
                if item.id.contains("\(scriptId)") { return true }
                return false
            }
        }
        
        // Try to find by scriptUUID first
        if let item = queueItems.first(where: { item in
            item.scriptUUID == scriptUUID || item.id == scriptUUID
        }) {
            return item
        }
        
        // Fallback: try to find by scriptId even if we have scriptUUID
        if let scriptId = scriptId {
            return queueItems.first { item in
                if item.scriptId == scriptId { return true }
                if item.id.contains("script_\(scriptId)") { return true }
                if item.id.contains("\(scriptId)") { return true }
                return false
            }
        }
        
        return nil
    }
    
    // MARK: - Call Management Integration
    /// Ends the current call when a remove event is received - no validation needed
    private func endCurrentCallIfMatches(scriptUUID: String?, scriptId: Int?) {
        let callKitManager = CallKitManager.shared
        
        print("📞 WebSocket remove event received - ending current call immediately")
        print("   - Current call state: \(callKitManager.currentCallState)")
        print("   - Removal scriptUUID: \(scriptUUID ?? "nil")")
        print("   - Removal scriptId: \(scriptId?.description ?? "nil")")
        
        // End the call immediately when any remove event is received
        if callKitManager.currentCallState != .idle {
            print("📞 Ending current call due to queue removal event")
            callKitManager.endCall()
        } else {
            print("📞 No active call to end")
        }
    }
    
    /// Terminates VoIP call if it matches the script_id from the removal event
    private func terminateVoIPCallIfMatching(scriptId: Int?) {
        guard let scriptId = scriptId else {
            print("📞 No script_id provided for VoIP call termination check")
            return
        }
        
        let callKitManager = CallKitManager.shared
        
        // Check if there's an active VoIP call
        guard callKitManager.currentCallState != .idle else {
            print("📞 No active VoIP call to terminate")
            return
        }
        
        // Check if the current call's script_id matches the removal script_id
        guard let currentCall = callKitManager.currentCall,
              let currentScriptId = currentCall.scriptId,
              currentScriptId == scriptId else {
            print("📞 Active VoIP call script_id (\(callKitManager.currentCall?.scriptId?.description ?? "nil")) doesn't match removal script_id (\(scriptId))")
            return
        }
        
        print("📞 Terminating VoIP call due to queue removal - script_id match: \(scriptId)")
        print("   - Caller: \(currentCall.displayName)")
        print("   - Script ID: \(currentScriptId)")
        print("   - Call State: \(callKitManager.currentCallState)")
        
        // Terminate the VoIP call
        callKitManager.endCall()
        
        print("✅ VoIP call terminated successfully due to queue removal")
    }
    
    /// Terminates Jitsi meeting if it matches the script_id from the removal event
    private func terminateJitsiMeetingIfMatching(scriptId: Int?, scriptUUID: String?) {
        let globalJitsiManager = GlobalJitsiManager.shared
        
        // Check if there's an active Jitsi meeting
        guard globalJitsiManager.isPresentingJitsi else {
            print("🎥 No active Jitsi meeting to terminate")
            return
        }
        
        // Check if we have script information to match
        guard let scriptId = scriptId else {
            print("🎥 No script_id provided for Jitsi meeting termination check")
            return
        }
        
        // Check if the current Jitsi meeting's script_id matches the removal script_id
        guard let currentJitsiParams = globalJitsiManager.jitsiParameters,
              let currentScriptId = currentJitsiParams.scriptId,
              currentScriptId == scriptId else {
            print("🎥 Active Jitsi meeting script_id (\(globalJitsiManager.jitsiParameters?.scriptId?.description ?? "nil")) doesn't match removal script_id (\(scriptId))")
            return
        }
        
        print("🎥 Terminating Jitsi meeting due to queue removal - script_id match: \(scriptId)")
        print("   - Room: \(currentJitsiParams.roomName)")
        print("   - Script ID: \(currentScriptId)")
        print("   - Script UUID: \(currentJitsiParams.scriptUUID ?? "nil")")
        
        // Terminate the Jitsi meeting
        globalJitsiManager.endCall()
        
        print("✅ Jitsi meeting terminated successfully due to queue removal")
    }
    
    /// Handles queue removal with background state awareness
    private func handleQueueRemovalWithBackgroundSupport(scriptId: Int?, scriptUUID: String?, patientName: String?) {
        // Check if app is in background or inactive state
        let appState = UIApplication.shared.applicationState
        let isBackground = appState == .background || appState == .inactive
        
        print("🗑️ Queue removal handling - App state: \(appState.rawValue) (\(isBackground ? "background/inactive" : "active"))")
        
        if isBackground {
            // Use VoIP push handler for background state
            print("📱 App in background - using VoIP push handler for queue removal")
            VoIPPushHandler.shared.handleQueueRemoval(
                scriptId: scriptId,
                scriptUUID: scriptUUID,
                patientName: patientName
            )
        } else {
            // Use normal WebSocket handling for foreground state
            print("📱 App in foreground - using normal WebSocket handling")
            terminateVoIPCallIfMatching(scriptId: scriptId)
        }
        
        // Always check for active Jitsi meetings regardless of app state
        // This ensures Jitsi meetings are terminated even when app is in lock screen state
        terminateJitsiMeetingIfMatching(scriptId: scriptId, scriptUUID: scriptUUID)
    }
    
    // MARK: - Queue Maintenance
    /// Debug method to print current queue state
    func debugQueueState() {
        print("🔍 Current Queue State:")
        print("   - Total items: \(queueItems.count)")
        for (index, item) in queueItems.enumerated() {
            print("   Item \(index + 1):")
            print("     - Patient: \(item.patientName)")
            print("     - Clinic: \(item.clinic)")
            print("     - ID: \(item.id)")
            print("     - Script ID: \(item.scriptId?.description ?? "nil")")
            print("     - Script UUID: \(item.scriptUUID ?? "nil")")
            print("     - Script Number: \(item.scriptNumber ?? "nil")")
            print("     - Clinic Slug: \(item.clinicSlug ?? "nil")")
        }
    }
    
    /// Clears all queue data (used during logout)
    func clearQueueData() {
        print("🗑️ WebSocketManager: Clearing all queue data")
        queueItems.removeAll()
        connectionStatus = .disconnected
        lastMessage = ""
        print("✅ WebSocketManager: Queue data cleared")
    }
    
    /// Periodically cleans up any duplicates that might have accumulated
    /// This is a safety net for edge cases where duplicates slip through
    func cleanupDuplicates() {
        let originalCount = queueItems.count
        let uniqueItems = deduplicateQueueItems(queueItems)
        
        if uniqueItems.count < originalCount {
            let duplicatesRemoved = originalCount - uniqueItems.count
            print("🧹 Queue cleanup completed: removed \(duplicatesRemoved) duplicate items")
            print("   - Before: \(originalCount) items")
            print("   - After: \(uniqueItems.count) items")
            queueItems = uniqueItems
        } else {
            print("✅ Queue cleanup: no duplicates found (\(originalCount) items)")
        }
    }
    
    /// Deduplicates queue items using the same logic as the API service
    private func deduplicateQueueItems(_ items: [QueueItem]) -> [QueueItem] {
        var seenIdentifiers: Set<String> = []
        var seenScriptUUIDs: Set<String> = []
        var seenScriptIds: Set<Int> = []
        var deduplicated: [QueueItem] = []
        
        for item in items {
            var isDuplicate = false
            
            // Check by scriptUUID first (most reliable identifier)
            if let scriptUUID = item.scriptUUID, !scriptUUID.isEmpty {
                if seenScriptUUIDs.contains(scriptUUID) {
                    isDuplicate = true
                } else {
                    seenScriptUUIDs.insert(scriptUUID)
                }
            }
            
            // Check by scriptId if no scriptUUID or not duplicate
            if !isDuplicate, let scriptId = item.scriptId, scriptId > 0 {
                if seenScriptIds.contains(scriptId) {
                    isDuplicate = true
                } else {
                    seenScriptIds.insert(scriptId)
                }
            }
            
            // Check by mapped ID as fallback
            if !isDuplicate {
                if seenIdentifiers.contains(item.id) {
                    isDuplicate = true
                } else {
                    seenIdentifiers.insert(item.id)
                }
            }
            
            if !isDuplicate {
                deduplicated.append(item)
            }
        }
        
        return deduplicated
    }
    
    // MARK: - Test helper
    func testBroadcast() {
        let urlString = "\(baseURL)/api/queue-list?user_id=\(currentUserId)&clinic_slug=cosmetic_app&script_id=270&clinic_name=Sample%20clinic&caller_name=Hllo&script_uuid=e8b401f1-90df-4d5d-af21-3bd2bdc0ccc2"
        guard let url = URL(string: urlString) else {
            
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                
            }
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                
                Task { @MainActor in
                    self?.lastMessage = "Broadcast triggered: \(responseString)"
                }
            }
        }.resume()
    }

    // MARK: - Keepalive and Reconnect helpers
    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.socket?.write(ping: Data())
        }
        
        // Start periodic cleanup timer (every 2 minutes)
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.cleanupDuplicates()
        }
    }

    private func stopTimers() {
        pingTimer?.invalidate()
        pingTimer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    private func scheduleReconnect() {
        guard shouldReconnect, !isConnected else { return }
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let base: TimeInterval = 1
        let delay = min(base * pow(2, Double(reconnectAttempts - 1)), maxReconnectDelay)
        
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.shouldReconnect, !self.isConnected else { return }
            self.setupWebSocket()
            self.connect()
        }
    }
}


