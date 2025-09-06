//
//  RealtimeTypes.swift
//  CosmeticTechMobile
//
//  Common realtime types used by async WebSocket implementations.
//

import Foundation

public enum RealtimeEvent: Sendable, Equatable {
    case connected
    case disconnected(code: URLSessionWebSocketTask.CloseCode, reason: String?)
    case text(String)
    case data(Data)
    case error(String)
}

public struct RealtimeConfig: Sendable {
    public var url: URL
    public var headers: [String: String] = [:]
    public var pingInterval: TimeInterval = 25
    public var handshakeTimeout: TimeInterval = 10
    public var enableCompression: Bool = true
    public init(url: URL) { self.url = url }
}

public protocol RealtimeClient: AnyObject {
    var events: AsyncStream<RealtimeEvent> { get }
    func connect() async
    func disconnect(code: URLSessionWebSocketTask.CloseCode?) async
    func send(text: String) async
    func send(data: Data) async
}


