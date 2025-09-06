//
//  ConfigurationService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation

// MARK: - Configuration Service Protocol (Interface Segregation Principle)
protocol ConfigurationServiceProtocol {
    var redirectURL: String { get set }
    var defaultRedirectURL: String { get }
    // Pusher
    var pusherKey: String { get }
    var pusherCluster: String { get }
    var pusherHost: String? { get }
    // Unified realtime config
    var broadcastConnection: String { get }
    var realtimeKey: String { get }
    var realtimeHost: String? { get }
    var realtimeCluster: String { get }
    var realtimePort: Int? { get }
    var realtimeUseTLS: Bool { get }
    var authEndpoint: String? { get }
    func loadConfiguration()
    func saveConfiguration()
    func resetToDefaults()
}

// MARK: - Configuration Service Implementation (Single Responsibility Principle)
class ConfigurationService: ConfigurationServiceProtocol {
    
    // MARK: - Properties
    private let userDefaults = UserDefaults.standard
    private let redirectURLKey = "redirect_url"
    // Pusher config keys (read-only for now)
    private let pusherKeyKey = "pusher_key"
    private let pusherClusterKey = "pusher_cluster"
    private let pusherHostKey = "pusher_host"
    // Reverb / Broadcast keys from Info.plist
    private let broadcastConnKey = "BROADCAST_CONNECTION"
    private let reverbAppKey = "REVERB_APP_KEY"
    private let reverbHostKey = "REVERB_HOST"
    private let reverbPortKey = "REVERB_PORT"
    private let reverbSchemeKey = "REVERB_SCHEME"
    private let authEndpointKey = "BROADCAST_AUTH_ENDPOINT"
    private let socketBaseURLKey = "SOCKET_BASE_URL"
    
    var redirectURL: String {
        get {
            return userDefaults.string(forKey: redirectURLKey) ?? defaultRedirectURL
        }
        set {
            userDefaults.set(newValue, forKey: redirectURLKey)
            saveConfiguration()
        }
    }
    
    var defaultRedirectURL: String {
        return "https://google.com"
    }

    // MARK: - Pusher (these would normally come from Info.plist or remote config)
    var pusherKey: String {
        // Order of precedence: UserDefaults -> Info.plist -> empty
        if let k = userDefaults.string(forKey: pusherKeyKey), !k.isEmpty { return k }
        if let k = Bundle.main.object(forInfoDictionaryKey: "PUSHER_APP_KEY") as? String, !k.isEmpty { return k }
        return ""
    }
    var pusherCluster: String {
        if let c = userDefaults.string(forKey: pusherClusterKey), !c.isEmpty { return c }
        if let c = Bundle.main.object(forInfoDictionaryKey: "PUSHER_APP_CLUSTER") as? String, !c.isEmpty { return c }
        return "ap1"
    }
    var pusherHost: String? {
        if let h = userDefaults.string(forKey: pusherHostKey), !h.isEmpty { return h }
        if let h = Bundle.main.object(forInfoDictionaryKey: "PUSHER_HOST") as? String, !h.isEmpty { return h }
        return nil
    }

    // MARK: - Unified realtime config (Pusher Channels vs Reverb)
    var broadcastConnection: String {
        (Bundle.main.object(forInfoDictionaryKey: broadcastConnKey) as? String)?.lowercased() ?? "pusher"
    }
    var realtimeKey: String {
        if broadcastConnection == "reverb" {
            if let k = Bundle.main.object(forInfoDictionaryKey: reverbAppKey) as? String, !k.isEmpty { return k }
        }
        return pusherKey
    }
    var realtimeHost: String? {
        if broadcastConnection == "reverb" {
            if let h = Bundle.main.object(forInfoDictionaryKey: reverbHostKey) as? String, !h.isEmpty { return h }
        }
        return pusherHost
    }
    var realtimeCluster: String {
        return pusherCluster
    }
    var realtimePort: Int? {
        if broadcastConnection == "reverb" {
            if let s = Bundle.main.object(forInfoDictionaryKey: reverbPortKey) as? String, let i = Int(s) { return i }
            if let i = Bundle.main.object(forInfoDictionaryKey: reverbPortKey) as? Int { return i }
        }
        return nil
    }
    var realtimeUseTLS: Bool {
        if broadcastConnection == "reverb" {
            let scheme = (Bundle.main.object(forInfoDictionaryKey: reverbSchemeKey) as? String)?.lowercased() ?? "http"
            return scheme == "https" || scheme == "wss"
        }
        return true
    }
    var authEndpoint: String? {
        // Provide a custom auth endpoint for private/presence channels if required by backend
        if let base = Bundle.main.object(forInfoDictionaryKey: socketBaseURLKey) as? String, !base.isEmpty {
            return base.hasSuffix("/") ? base + "broadcasting/auth" : base + "/broadcasting/auth"
        }
        if let url = Bundle.main.object(forInfoDictionaryKey: authEndpointKey) as? String, !url.isEmpty {
            return url
        }
        return nil
    }
    
    // MARK: - Initialization
    init() {
        loadConfiguration()
    }
    
    // MARK: - Configuration Management
    func loadConfiguration() {
        // Load configuration from UserDefaults
        // If no configuration exists, use defaults
        if userDefaults.object(forKey: redirectURLKey) == nil {
            userDefaults.set(defaultRedirectURL, forKey: redirectURLKey)
        }
        // Preload default Pusher cluster if not set
        if userDefaults.object(forKey: pusherClusterKey) == nil {
            userDefaults.set("ap1", forKey: pusherClusterKey)
        }
    }
    
    func saveConfiguration() {
        userDefaults.synchronize()
    }
    
    func resetToDefaults() {
        userDefaults.removeObject(forKey: redirectURLKey)
        userDefaults.set(defaultRedirectURL, forKey: redirectURLKey)
        saveConfiguration()
    }
}

// MARK: - Configuration Service Factory (Dependency Inversion Principle)
class ConfigurationServiceFactory {
    static func createConfigurationService() -> ConfigurationServiceProtocol {
        return ConfigurationService()
    }
} 