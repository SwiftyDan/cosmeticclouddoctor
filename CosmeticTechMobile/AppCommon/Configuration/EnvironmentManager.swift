//
//  EnvironmentManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import Combine
import UIKit

// MARK: - API Environment Enum
enum APIEnvironment: String, CaseIterable, Codable {
    case production = "production"
    case staging = "staging"
    case development = "development"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .development: return "Development"
        case .custom: return "Custom"
        }
    }
}

// MARK: - UserDefaults Property Wrappers
@propertyWrapper
struct UserDefaultsCodable<Value: Codable> {
    private let key: String
    private let defaultValue: Value
    private let notificationName: Notification.Name
    
    var projectedValue: AnyPublisher<Value, Never> {
        NotificationCenter.default
            .publisher(for: notificationName)
            .compactMap { $0.object as? Value }
            .prepend(wrappedValue)
            .eraseToAnyPublisher()
    }
    
    var wrappedValue: Value {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let value = try? JSONDecoder().decode(Value.self, from: data) {
                return value
            }
            return defaultValue
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.set(newValue as? Any, forKey: key)
            }
            NotificationCenter.default.post(name: notificationName, object: newValue)
        }
    }
    
    init(_ key: String, default: Value) {
        self.key = key
        self.defaultValue = `default`
        self.notificationName = Notification.Name("EnvironmentManager.\(key)")
    }
}

@propertyWrapper
struct UserDefaultsReadOnly<Value: Codable> {
    private let key: String
    private let defaultValue: Value
    
    var wrappedValue: Value {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(Value.self, from: data) {
            return value
        }
        return defaultValue
    }
    
    init(_ key: String, default: Value) {
        self.key = key
        self.defaultValue = `default`
    }
}

// MARK: - Environment Manager
class EnvironmentManager: ObservableObject {
    static let shared = EnvironmentManager()
    
    // MARK: - UserDefaults
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Published Properties
    @Published var currentEnvironment: APIEnvironment = .production
    @Published var currentAPIURL: String = ""
    @Published var currentJitsiURL: String = ""
    @Published var currentSocketURL: String = ""
    
    // MARK: - UserDefaults Properties
    private var _selectedEnvironment: APIEnvironment = .production
    private var _customAPIURL: String = "https://your-custom-api.com/api"
    private var _customJitsiURL: String = "https://your-custom-jitsi.com"
    private var _customSocketURL: String = "https://your-custom-socket.com"
    
    var selectedEnvironment: APIEnvironment {
        get { _selectedEnvironment }
        set { 
            _selectedEnvironment = newValue
            currentEnvironment = newValue
            // Update UserDefaults
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: "API_ENVIRONMENT")
            }
            updateURLs()
            updateSettingsDisplay()
            NotificationCenter.default.post(name: .environmentChanged, object: newValue)
            APIConfiguration.shared.refreshEndpoints()
        }
    }
    
    var customAPIURL: String {
        get { _customAPIURL }
        set { 
            _customAPIURL = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: "CUSTOM_API_URL")
            }
        }
    }
    
    var customJitsiURL: String {
        get { _customJitsiURL }
        set { 
            _customJitsiURL = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: "CUSTOM_JITSI_URL")
            }
        }
    }
    
    var customSocketURL: String {
        get { _customSocketURL }
        set { 
            _customSocketURL = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: "CUSTOM_SOCKET_URL")
            }
        }
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        // Initialize from UserDefaults first
        loadFromUserDefaults()
        setupEnvironment()
        observeEnvironmentChanges()
    }
    
    private func loadFromUserDefaults() {
        // Load environment from UserDefaults (prioritize data format, fallback to string)
        if let data = userDefaults.data(forKey: "API_ENVIRONMENT"),
           let env = try? JSONDecoder().decode(APIEnvironment.self, from: data) {
            _selectedEnvironment = env
            currentEnvironment = env
        } else if let envString = userDefaults.string(forKey: "API_ENVIRONMENT"),
                  let env = APIEnvironment(rawValue: envString) {
            _selectedEnvironment = env
            currentEnvironment = env
        } else {
            _selectedEnvironment = .production
            currentEnvironment = .production
        }
        
        // Load custom URLs (Data-encoded via Codable wrapper)
        if let dataApi = userDefaults.data(forKey: "CUSTOM_API_URL"),
           let api = try? JSONDecoder().decode(String.self, from: dataApi) {
            _customAPIURL = api
        } else if let apiString = userDefaults.string(forKey: "CUSTOM_API_URL") {
            _customAPIURL = apiString
        }
        
        if let dataJitsi = userDefaults.data(forKey: "CUSTOM_JITSI_URL"),
           let jitsi = try? JSONDecoder().decode(String.self, from: dataJitsi) {
            _customJitsiURL = jitsi
        } else if let jitsiString = userDefaults.string(forKey: "CUSTOM_JITSI_URL") {
            _customJitsiURL = jitsiString
        }
        
        if let dataSocket = userDefaults.data(forKey: "CUSTOM_SOCKET_URL"),
           let socket = try? JSONDecoder().decode(String.self, from: dataSocket) {
            _customSocketURL = socket
        } else if let socketString = userDefaults.string(forKey: "CUSTOM_SOCKET_URL") {
            _customSocketURL = socketString
        }
    }
    
    private func setupEnvironment() {
        updateURLs()
        updateSettingsDisplay()
    }
    
    private func observeEnvironmentChanges() {
        // Observe environment changes
        NotificationCenter.default.publisher(for: .environmentChanged)
            .compactMap { $0.object as? APIEnvironment }
            .sink { [weak self] newEnvironment in
                self?.currentEnvironment = newEnvironment
                self?.updateURLs()
                self?.updateSettingsDisplay()
            }
            .store(in: &cancellables)
    }
    
    private func updateURLs() {
        let urls = self.urls(for: currentEnvironment)
        currentAPIURL = urls.api
        currentJitsiURL = urls.jitsi
        currentSocketURL = urls.socket
    }
    
    private func updateSettingsDisplay() {
        // Update display values for settings
        userDefaults.set(currentAPIURL, forKey: "CURRENT_API_URL")
        userDefaults.set(currentJitsiURL, forKey: "CURRENT_JITSI_URL")
    }
    
    // MARK: - Public Methods
    func setEnvironment(_ environment: APIEnvironment) {
        selectedEnvironment = environment
    }
    
    func forceSetEnvironment(_ environment: APIEnvironment) {
        selectedEnvironment = environment
        // Also save as string for compatibility
        userDefaults.set(environment.rawValue, forKey: "API_ENVIRONMENT")
    }
    
    private func urls(for environment: APIEnvironment) -> (api: String, jitsi: String, socket: String) {
        switch environment {
        case .production:
            return (
                api: "https://cosmeticcloud.tech/api",
                jitsi: "https://video-chat.cosmeticcloud.tech",
                socket: "https://cosmeticcloud.tech"
            )
        case .staging:
            return (
                api: "https://staging.cosmeticcloud.tech/api",
                jitsi: "https://staging-video-chat.cosmeticcloud.tech",
                socket: "https://staging.cosmeticcloud.tech"
            )
        case .development:
            return (
                api: "https://testing.cosmeticcloud.tech/api",
                jitsi: "https://video-chat.cosmeticcloud.tech",
                socket: "https://testing.cosmeticcloud.tech"
            )
        case .custom:
            return (
                api: _customAPIURL,
                jitsi: _customJitsiURL,
                socket: _customSocketURL
            )
        }
    }
    
    func getEnvironmentInfo() -> String {
        let urls = self.urls(for: currentEnvironment)
        return """
        Environment: \(currentEnvironment.displayName)
        API URL: \(urls.api)
        Jitsi URL: \(urls.jitsi)
        Socket URL: \(urls.socket)
        """
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let environmentChanged = Notification.Name("EnvironmentManager.environmentChanged")
    static let apiURLChanged = Notification.Name("EnvironmentManager.apiURLChanged")
    static let jitsiURLChanged = Notification.Name("EnvironmentManager.jitsiURLChanged")
    static let socketURLChanged = Notification.Name("EnvironmentManager.socketURLChanged")
}