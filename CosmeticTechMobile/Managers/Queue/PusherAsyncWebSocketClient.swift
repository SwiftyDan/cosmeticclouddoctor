//
//  PusherAsyncWebSocketClient.swift
//  CosmeticTechMobile
//
//  Lightweight, actor‑isolated WebSocket client using URLSessionWebSocketTask.
//  Designed for Laravel Reverb / Pusher‑compatible servers.
//  iOS 15+ only. Falls back to Starscream elsewhere via WebSocketManager.
//

import Foundation
import Network

@available(iOS 15.0, *)
public actor PusherAsyncWebSocketClient: RealtimeClient {
	public nonisolated var events: AsyncStream<RealtimeEvent> { _events }

	private let config: RealtimeConfig
	private let session: URLSession
	private var task: URLSessionWebSocketTask?
	private var receiveTask: Task<Void, Never>?
	private var pingTask: Task<Void, Never>?
	private var monitor: NWPathMonitor?

	private let _events: AsyncStream<RealtimeEvent>
	private let continuation: AsyncStream<RealtimeEvent>.Continuation

	public init(config: RealtimeConfig) {
		self.config = config
		let sessionConfig = URLSessionConfiguration.default
		sessionConfig.timeoutIntervalForRequest = config.handshakeTimeout
		sessionConfig.httpAdditionalHeaders = config.headers
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		sessionConfig.waitsForConnectivity = true
		self.session = URLSession(configuration: sessionConfig)

		var stream: AsyncStream<RealtimeEvent>! = nil
		var cont: AsyncStream<RealtimeEvent>.Continuation! = nil
		stream = AsyncStream<RealtimeEvent> { continuation in
			cont = continuation
		}
		_events = stream
		continuation = cont

		setupNetworkMonitoring()
	}

	public func connect() async {
		guard task == nil else { return }
		await createAndResumeTask()
	}

	public func disconnect(code: URLSessionWebSocketTask.CloseCode? = nil) async {
		pingTask?.cancel(); pingTask = nil
		receiveTask?.cancel(); receiveTask = nil
		monitor?.cancel(); monitor = nil
		if let t = task { t.cancel(with: code ?? .normalClosure, reason: nil) }
		task = nil
		continuation.yield(.disconnected(code: .normalClosure, reason: "client requested"))
		continuation.finish()
	}

	public func send(text: String) async {
		guard let task else { return }
		do { try await task.send(.string(text)) } catch { continuation.yield(.error("send text: \(error.localizedDescription)")) }
	}

	public func send(data: Data) async {
		guard let task else { return }
		do { try await task.send(.data(data)) } catch { continuation.yield(.error("send data: \(error.localizedDescription)")) }
	}

	// MARK: - Private

    private func createAndResumeTask() async {
        var request = URLRequest(url: config.url)
        // Apply permessage-deflate if enabled
        request.setValue(config.enableCompression ? "permessage-deflate" : nil, forHTTPHeaderField: "Sec-WebSocket-Extensions")
        // Propagate custom headers (e.g., Sec-WebSocket-Protocol for Pusher/Reverb)
        for (k, v) in config.headers { request.setValue(v, forHTTPHeaderField: k) }
		let t = session.webSocketTask(with: request)
		task = t
		t.resume()
		continuation.yield(.connected)
		startReceiveLoop()
		startPingLoop()
	}

	private func startReceiveLoop() {
		receiveTask?.cancel()
		receiveTask = Task { [weak self] in
			guard let self else { return }
			await self.receiveLoop()
		}
	}

	private func startPingLoop() {
		guard config.pingInterval > 0 else { return }
		pingTask?.cancel()
		pingTask = Task { [weak self] in
			guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.config.pingInterval * 1_000_000_000))
                guard let task = await self.task else { continue }
                task.sendPing { [weak self] error in
                    guard let self else { return }
                    if let error {
                        Task { await self.continuation.yield(.error("ping: \(error.localizedDescription)")) }
                    }
                }
            }
		}
	}

	private func receiveLoop() async {
		guard let task else { return }
		while !Task.isCancelled {
			do {
				let message = try await task.receive()
				switch message {
				case .string(let text):
					continuation.yield(.text(text))
				case .data(let data):
					continuation.yield(.data(data))
				@unknown default:
					continuation.yield(.error("Unknown message type"))
				}
			} catch {
				await handleError(error)
				break
			}
		}
	}

	private func handleError(_ error: Error) async {
		continuation.yield(.error(error.localizedDescription))
		task = nil
	}

	private func setupNetworkMonitoring() {
		let monitor = NWPathMonitor()
		self.monitor = monitor
		let queue = DispatchQueue(label: "ws.monitor")
		monitor.pathUpdateHandler = { [weak self] path in
			guard let self else { return }
			Task { await self.networkChanged(status: path.status) }
		}
		monitor.start(queue: queue)
	}

	private func networkChanged(status: NWPath.Status) async {
		if status == .satisfied, task == nil {
			await createAndResumeTask()
		}
	}
}


