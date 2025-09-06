//
//  StarscreamQueueService.swift
//  CosmeticTechMobile
//
//  Real-time Queue list via Starscream (minimal Pusher Channels compatibility for public/private)
//

import Foundation
import Combine
import Starscream

protocol QueueRealtimeServiceProtocol: AnyObject {
    var queueItemsPublisher: AnyPublisher<[QueueItem], Never> { get }
    func connect(appKey: String, cluster: String, host: String?)
    func subscribe(toChannel channelName: String, eventName: String)
    func disconnect()
}

final class StarscreamQueueService: QueueRealtimeServiceProtocol, WebSocketDelegate {
    // MARK: - Public
    var queueItemsPublisher: AnyPublisher<[QueueItem], Never> { queueSubject.eraseToAnyPublisher() }

    // MARK: - Private
    private var socket: WebSocket?
    private let queueSubject = CurrentValueSubject<[QueueItem], Never>([])
    private var isConnected: Bool = false
    private var socketId: String?
    private var currentUserUUID: String {
        if let uuid: String = KeychainService().retrieve(key: "user_uuid", type: String.self) { return uuid }
        return ""
    }
    private var subscribedChannelName: String?
    private var targetEventName: String?
    private var lastIsPrivateOrPresence: Bool = false
    private var uuidSubscribeRetryTask: Task<Void, Never>?

    // MARK: - Lifecycle
    func connect(appKey: String, cluster: String, host: String?) {
        guard !appKey.isEmpty else {
            
            return
        }

        let cfg = ConfigurationServiceFactory.createConfigurationService()
        let urlString: String = {
            if let host, !host.isEmpty {
                let scheme = cfg.realtimeUseTLS ? "wss" : "ws"
                let port = cfg.realtimePort ?? (cfg.realtimeUseTLS ? 443 : 6001)
                let base = port == 80 || port == 443 ? host : "\(host):\(port)"
                return "\(scheme)://\(base)/app/\(appKey)?protocol=7&client=swift&version=1.0&flash=false"
            } else {
                // Fallback to public Pusher host by cluster
                return "wss://ws-\(cluster).pusher.com/app/\(appKey)?protocol=7&client=swift&version=1.0&flash=false"
            }
        }()

        guard let url = URL(string: urlString) else {
            
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Pusher Channels and Laravel Reverb expect the subprotocol header
        request.setValue("pusher-channels-protocol-7", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let socket = WebSocket(request: request)
        socket.delegate = self
        // Auto-respond to pings to keep the connection alive
        socket.respondToPingWithPong = true
        self.socket = socket

        let maskedKey: String = {
            let suffix = appKey.suffix(4)
            return "****\(suffix)"
        }()
        
        socket.connect()
    }

    func subscribe(toChannel channelName: String, eventName: String) {
        let uuidSuffix = currentUserUUID.isEmpty ? "" : ".\(currentUserUUID)"
        subscribedChannelName = "\(channelName)\(uuidSuffix)"
        targetEventName = eventName
        lastIsPrivateOrPresence = channelName.hasPrefix("private-") || channelName.hasPrefix("presence-")

        // If already connected and have socket id, try to subscribe immediately
        attemptSubscriptionIfPossible()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
        socketId = nil
        subscribedChannelName = nil
        targetEventName = nil
    }

    deinit {
        disconnect()
    }

    // MARK: - WebSocketDelegate
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            isConnected = true
            // subscribe when connected
            // For public channels we can subscribe immediately
            attemptSubscriptionIfPossible()
        case .disconnected(let reason, let code):
            isConnected = false
            break
        case .text(let string):
            // handle JSON payloads
            handleIncomingText(string)
        case .binary(let data):
            break
        case .error(let error):
            break
        case .viabilityChanged(let viable):
            break
        case .reconnectSuggested(let suggested):
            break
        case .cancelled:
            isConnected = false
            break
        case .ping(_):
            break
        case .pong(_):
            break
        case .peerClosed:
            isConnected = false
            break
        }
    }

    // MARK: - Private helpers
    private func handleIncomingText(_ text: String) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            
            return
        }
        let event = json["event"] as? String ?? ""
        let channel = json["channel"] as? String

        // Handle Pusher ping to keepalive
        if event == "pusher:ping" {
            send(json: ["event": "pusher:pong"]) 
            return
        }

        // Log subscription errors
        if event == "pusher:error" {
            // ignore
        }
        if event == "pusher:subscription_error" {
            // ignore
        }

        // Pusher handshake: pusher:connection_established
        if event == "pusher:connection_established" {
            if let dataString = json["data"] as? String,
               let data = dataString.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                socketId = payload["socket_id"] as? String
                
                attemptSubscriptionIfPossible()
                return
            }
            if let payload = json["data"] as? [String: Any] {
                socketId = payload["socket_id"] as? String
                
                attemptSubscriptionIfPossible()
                return
            }
            // ignore unparseable
            return
        }

        // Subscription succeeded
        if event == "pusher_internal:subscription_succeeded" {
            // subscribed
        }

        // Regular channel event
        guard let subscribedChannelName, let targetEventName else { return }
        let matchesEvent = (event == targetEventName) || (event.hasSuffix(".\(targetEventName)"))
        guard channel == subscribedChannelName, matchesEvent else { return }

        // Pusher wraps data as a JSON string
        if let dataString = json["data"] as? String,
           let data = dataString.data(using: .utf8) {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                handleEventDictionary(dict)
                return
            }
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                // Wrap array under "queue" if backend sends list
                handleEventDictionary(["queue": array])
                return
            }
        }

        // Or allow direct dictionary payloads
        if let dict = json["data"] as? [String: Any] {
            handleEventDictionary(dict)
        }
    }

    private func attemptSubscriptionIfPossible() {
        guard isConnected, let channel = subscribedChannelName else { return }

        if lastIsPrivateOrPresence {
            guard let socketId else { return }
            // Minimal private channel support via auth endpoint
            guard let authUrl = ConfigurationServiceFactory.createConfigurationService().authEndpoint else {
                
                return
            }
            fetchAuthToken(authUrl: authUrl, socketId: socketId, channelName: channel) { [weak self] auth in
                guard let self else { return }
                guard let auth else {
                    
                    return
                }
                let subscribePayload: [String: Any] = [
                    "event": "pusher:subscribe",
                    "data": [
                        "channel": channel,
                        "auth": auth
                    ]
                ]
                self.send(json: subscribePayload)
            }
        } else {
            let subscribePayload: [String: Any] = [
                "event": "pusher:subscribe",
                "data": [
                    "channel": channel
                ]
            ]
            send(json: subscribePayload)
        }
    }

    private func fetchAuthToken(authUrl: String, socketId: String, channelName: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: authUrl) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let token: String = KeychainService().retrieve(key: "auth_token", type: String.self) {
            let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
            req.setValue(header, forHTTPHeaderField: "Authorization")
        }
        let encoded = "socket_id=\(socketId)&channel_name=\(channelName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelName)"
        req.httpBody = encoded.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(nil); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let auth = json["auth"] as? String else {
                
                completion(nil)
                return
            }
            completion(auth)
        }.resume()
        
    }

    private func send(json: [String: Any]) {
        guard let socket else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: json), let text = String(data: data, encoding: .utf8) else { return }
        
        socket.write(string: text)
    }

    private func handleEventDictionary(_ dict: [String: Any]) {
        // Removal support scoped to doctor_user_id + script_uuid
        if let action = (dict["action"] as? String)?.lowercased(), action == "remove" {
            var updated = queueSubject.value
            let doctorIdFromEvent: Int? = (dict["doctor_user_id"] as? Int) ?? Int((dict["doctor_user_id"] as? String) ?? "")
            if let targetDoctorId = doctorIdFromEvent {
                let myId = KeychainService().retrieve(key: "user_data", type: User.self)?.userId ?? -1
                if targetDoctorId != myId { return }
            }

            let uuid: String? = (dict["script_uuid"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            // Handle both string and integer script_id types from WebSocket
            let sid: Int? = {
                if let intValue = dict["script_id"] as? Int {
                    return intValue > 0 ? intValue : nil
                } else if let stringValue = dict["script_id"] as? String, let intValue = Int(stringValue) {
                    return intValue > 0 ? intValue : nil
                }
                return nil
            }()

            updated.removeAll { item in
                if let uuid, item.id == uuid || item.scriptUUID == uuid { return true }
                if let sid, item.id == "script_\(sid)" || item.scriptId == sid { return true }
                return false
            }
            queueSubject.send(updated)
            return
        }

        let updatedList = QueueEventMapper.mapToQueueItems(from: dict, current: queueSubject.value)
        if let updatedList {
            
            queueSubject.send(updatedList)
        } else {
            
        }
    }
}

// MARK: - Queue Event Mapper (Single Responsibility)
private enum QueueEventMapper {
    /// Maps a realtime payload into a queue list. Returns nil if payload is not understood.
    static func mapToQueueItems(from dict: [String: Any], current: [QueueItem]) -> [QueueItem]? {
        // Direct queue list
        if let items = dict["queue"] as? [[String: Any]] {
            return items.compactMap(QueueItem.fromDictionary)
        }
        // Single item
        if let item = dict["item"] as? [String: Any], let newItem = QueueItem.fromDictionary(item) {
            var updated = current
            if let idx = updated.firstIndex(where: { $0.id == newItem.id }) {
                updated[idx] = newItem
            } else {
                updated.insert(newItem, at: 0)
            }
            return updated
        }
        // Expected broadcast payload (no wrapper keys)
        if let broadcastItem = QueueItem.fromBroadcastPayload(dict) {
            var updated = current
            if let idx = updated.firstIndex(where: { $0.id == broadcastItem.id }) {
                updated[idx] = broadcastItem
            } else {
                updated.insert(broadcastItem, at: 0)
            }
            return updated
        }
        return nil
    }
}


