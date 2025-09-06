//
//  EnvironmentManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/13/25.
//

import Foundation
import Combine

// MARK: - Environment Types
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
    
    // URL properties removed to prevent circular dependency
    // URLs are now resolved in EnvironmentManager.urls(for:) method
}

// MARK: - Property Wrappers
@propertyWrapper
struct UserDefaultsReadAndWrite<Value: Codable> {
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
                UserDefaults.standard.set(data, forKey: "API_ENVIRONMENT")
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
                UserDefaults.standard.set(data, forKey: "CUSTOM_API_URL")
            }
        }
    }
    
    var customJitsiURL: String {
        get { _customJitsiURL }
        set { 
            _customJitsiURL = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "CUSTOM_JITSI_URL")
            }
        }
    }
    
    var customSocketURL: String {
        get { _customSocketURL }
        set { 
            _customSocketURL = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "CUSTOM_SOCKET_URL")
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
        observeUserDefaultsChanges()
    }
    
    private func loadFromUserDefaults() {
        // Load environment from UserDefaults (Data-encoded via Codable wrapper)
        if let data = UserDefaults.standard.data(forKey: "API_ENVIRONMENT"),
           let env = try? JSONDecoder().decode(APIEnvironment.self, from: data) {
            _selectedEnvironment = env
            currentEnvironment = env
        } else {
            _selectedEnvironment = .production
            currentEnvironment = .production
        }
        
        // Load custom URLs (Data-encoded via Codable wrapper)
        if let dataApi = UserDefaults.standard.data(forKey: "CUSTOM_API_URL"),
           let api = try? JSONDecoder().decode(String.self, from: dataApi) {
            _customAPIURL = api
        } else {
            _customAPIURL = "https://your-custom-api.com/api"
        }
        if let dataJitsi = UserDefaults.standard.data(forKey: "CUSTOM_JITSI_URL"),
           let jitsi = try? JSONDecoder().decode(String.self, from: dataJitsi) {
            _customJitsiURL = jitsi
        } else {
            _customJitsiURL = "https://your-custom-jitsi.com"
        }
        if let dataSocket = UserDefaults.standard.data(forKey: "CUSTOM_SOCKET_URL"),
           let sock = try? JSONDecoder().decode(String.self, from: dataSocket) {
            _customSocketURL = sock
        } else {
            _customSocketURL = "https://your-custom-socket.com"
        }
    }
    
    // MARK: - Setup
    private func setupEnvironment() {
        // Use the loaded environment, not the property wrapper
        updateURLs()
        print("🌐 EnvironmentManager initialized with: \(currentEnvironment.displayName)")
        print("🔗 API URL: \(currentAPIURL)")
        print("🎥 Jitsi URL: \(currentJitsiURL)")
        print("🔌 Socket URL: \(currentSocketURL)")
    }
    
    private func observeEnvironmentChanges() {
        // Observe environment changes from NotificationCenter
        NotificationCenter.default.publisher(for: .environmentChanged)
            .sink { [weak self] notification in
                if let newEnvironment = notification.object as? APIEnvironment {
                    self?.currentEnvironment = newEnvironment
                    self?.updateURLs()
                    self?.updateSettingsDisplay()
                    
                    // Propagate to API endpoints and observers
                    NotificationCenter.default.post(
                        name: .environmentChanged,
                        object: nil,
                        userInfo: [
                            "environment": newEnvironment,
                            "apiURL": self?.currentAPIURL ?? "",
                            "jitsiURL": self?.currentJitsiURL ?? "",
                            "socketURL": self?.currentSocketURL ?? ""
                        ]
                    )
                    APIConfiguration.shared.refreshEndpoints()
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeUserDefaultsChanges() {
        // Observe UserDefaults changes from Settings app
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.handleUserDefaultsChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleUserDefaultsChange() {
        // Check if environment changed in Settings app
        let newEnvironment: APIEnvironment
        if let envString = UserDefaults.standard.string(forKey: "API_ENVIRONMENT"), let env = APIEnvironment(rawValue: envString) {
            newEnvironment = env
        } else if let data = UserDefaults.standard.data(forKey: "API_ENVIRONMENT"), let env = try? JSONDecoder().decode(APIEnvironment.self, from: data) {
            newEnvironment = env
        } else {
            newEnvironment = .production
        }

        if newEnvironment != currentEnvironment {
            print("🌐 Environment changed from Settings app: \(newEnvironment.displayName)")
            currentEnvironment = newEnvironment
            updateURLs()
            updateSettingsDisplay()
            
            // Post notification for environment change
            NotificationCenter.default.post(
                name: .environmentChanged,
                object: nil,
                userInfo: [
                    "environment": newEnvironment,
                    "apiURL": currentAPIURL,
                    "jitsiURL": currentJitsiURL,
                    "socketURL": currentSocketURL
                ]
            )
            // Also refresh API endpoints so any cached references pick up the new URLs
            APIConfiguration.shared.refreshEndpoints()
            print("🌐 Environment propagation complete: \(currentEnvironment.displayName)")
            print("🔗 API URL: \(currentAPIURL)")
            print("🎥 Jitsi URL: \(currentJitsiURL)")
            print("🔌 Socket URL: \(currentSocketURL)")
        }

        // Check for custom URL changes
        let newCustomAPIURL = UserDefaults.standard.string(forKey: "CUSTOM_API_URL") ?? "https://your-custom-api.com/api"
        let newCustomJitsiURL = UserDefaults.standard.string(forKey: "CUSTOM_JITSI_URL") ?? "https://your-custom-jitsi.com"
        let newCustomSocketURL = UserDefaults.standard.string(forKey: "CUSTOM_SOCKET_URL") ?? "https://your-custom-socket.com"
        
        if newCustomAPIURL != customAPIURL || newCustomJitsiURL != customJitsiURL || newCustomSocketURL != customSocketURL {
            customAPIURL = newCustomAPIURL
            customJitsiURL = newCustomJitsiURL
            customSocketURL = newCustomSocketURL
            
            if currentEnvironment == .custom {
                updateURLs()
                updateSettingsDisplay()
                
                // Post notification for custom URL changes
                NotificationCenter.default.post(
                    name: .environmentChanged,
                    object: nil,
                    userInfo: [
                        "environment": currentEnvironment,
                        "apiURL": currentAPIURL,
                        "jitsiURL": currentJitsiURL,
                        "socketURL": currentSocketURL
                    ]
                )
            }
        }
    }
    
    // MARK: - Public Methods
    func setEnvironment(_ environment: APIEnvironment) {
        // Update internal state
        _selectedEnvironment = environment
        currentEnvironment = environment
        
        // Update UserDefaults
        if let data = try? JSONEncoder().encode(environment) {
            UserDefaults.standard.set(data, forKey: "API_ENVIRONMENT")
        }
        UserDefaults.standard.synchronize()
        
        updateURLs()
        updateSettingsDisplay()
        
        // Post notification for environment change
        NotificationCenter.default.post(
            name: .environmentChanged,
            object: environment,
            userInfo: [
                "environment": environment,
                "apiURL": currentAPIURL,
                "jitsiURL": currentJitsiURL,
                "socketURL": currentSocketURL
            ]
        )
        APIConfiguration.shared.refreshEndpoints()
        
        print("🌐 Environment changed to: \(environment.displayName)")
        print("🔗 API URL: \(currentAPIURL)")
        print("🎥 Jitsi URL: \(currentJitsiURL)")
        print("🔌 Socket URL: \(currentSocketURL)")
    }
    
    func updateCustomURLs(api: String, jitsi: String, socket: String) {
        // Update UserDefaults directly
        UserDefaults.standard.set(api, forKey: "CUSTOM_API_URL")
        UserDefaults.standard.set(jitsi, forKey: "CUSTOM_JITSI_URL")
        UserDefaults.standard.set(socket, forKey: "CUSTOM_SOCKET_URL")
        UserDefaults.standard.synchronize()
        
        // Update properties
        customAPIURL = api
        customJitsiURL = jitsi
        customSocketURL = socket
        
        // Update URLs if we're in custom mode
        if currentEnvironment == .custom {
            updateURLs()
            updateSettingsDisplay()
        }
    }
    
    func resetToDefaults() {
        // Update UserDefaults directly with encoded values
        if let dataEnv = try? JSONEncoder().encode(APIEnvironment.production) {
            UserDefaults.standard.set(dataEnv, forKey: "API_ENVIRONMENT")
        }
        if let dataApi = try? JSONEncoder().encode("https://your-custom-api.com/api") {
            UserDefaults.standard.set(dataApi, forKey: "CUSTOM_API_URL")
        }
        if let dataJitsi = try? JSONEncoder().encode("https://your-custom-jitsi.com") {
            UserDefaults.standard.set(dataJitsi, forKey: "CUSTOM_JITSI_URL")
        }
        if let dataSock = try? JSONEncoder().encode("https://your-custom-socket.com") {
            UserDefaults.standard.set(dataSock, forKey: "CUSTOM_SOCKET_URL")
        }
        UserDefaults.standard.synchronize()
        
        // Update properties
        currentEnvironment = .production
        customAPIURL = "https://your-custom-api.com/api"
        customJitsiURL = "https://your-custom-jitsi.com"
        customSocketURL = "https://your-custom-socket.com"
        
        // Update URLs
        updateURLs()
        updateSettingsDisplay()
    }
    
    func refreshFromUserDefaults() {
        // Reload from UserDefaults and update if changed
        var newEnvironment: APIEnvironment = .production
        
        // Try data-based approach first (new method)
        if let data = UserDefaults.standard.data(forKey: "API_ENVIRONMENT"),
           let env = try? JSONDecoder().decode(APIEnvironment.self, from: data) {
            newEnvironment = env
        }
        // Fallback to string-based approach (old method)
        else if let envString = UserDefaults.standard.string(forKey: "API_ENVIRONMENT"),
                let env = APIEnvironment(rawValue: envString) {
            newEnvironment = env
        }
        
        print("🔄 Refreshing from UserDefaults...")
        print("   Current: \(currentEnvironment.displayName)")
        print("   UserDefaults: \(newEnvironment.displayName)")
        
        if newEnvironment != currentEnvironment {
            print("🌐 Environment changed from Settings app: \(newEnvironment.displayName)")
            _selectedEnvironment = newEnvironment
            currentEnvironment = newEnvironment
            updateURLs()
            updateSettingsDisplay()
            
            // Post notification for environment change
            NotificationCenter.default.post(
                name: .environmentChanged,
                object: nil,
                userInfo: [
                    "environment": newEnvironment,
                    "apiURL": currentAPIURL,
                    "jitsiURL": currentJitsiURL,
                    "socketURL": currentSocketURL
                ]
            )
            
            // Refresh API configuration
            APIConfiguration.shared.refreshEndpoints()
        } else {
            print("✅ Environment unchanged: \(currentEnvironment.displayName)")
        }
        
        // Debug current state
        debugCurrentState()
    }
    
    // MARK: - Private Methods
    private func urls(for environment: APIEnvironment) -> (api: String, jitsi: String, socket: String) {
        // Jitsi URL is always the same across all environments
        let jitsiURL = "https://video-chat.cosmeticcloud.tech"
        
        switch environment {
        case .production:
            return (
                api: "https://cosmeticcloud.tech/api",
                jitsi: jitsiURL,
                socket: "https://cosmeticcloud.tech"
            )
        case .staging:
            return (
                api: "https://staging.cosmeticcloud.tech/api",
                jitsi: jitsiURL,
                socket: "https://staging.cosmeticcloud.tech"
            )
        case .development:
            return (
                api: "https://testing.cosmeticcloud.tech/api",
                jitsi: jitsiURL,
                socket: "https://testing.cosmeticcloud.tech"
            )
        case .custom:
            return (
                api: customAPIURL,
                jitsi: jitsiURL, // Use the same Jitsi URL for custom environment too
                socket: customSocketURL
            )
        }
    }
    
    private func updateURLs() {
        let urls = urls(for: currentEnvironment)
        currentAPIURL = urls.api
        currentJitsiURL = urls.jitsi
        currentSocketURL = urls.socket
    }
    
    private func updateSettingsDisplay() {
        // Update the display values in Settings app
        UserDefaults.standard.set(currentAPIURL, forKey: "CURRENT_API_URL")
        UserDefaults.standard.set(currentJitsiURL, forKey: "CURRENT_JITSI_URL")
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Environment Info
    func getEnvironmentInfo() -> String {
        return """
        Environment: \(currentEnvironment.displayName)
        API URL: \(currentAPIURL)
        Jitsi URL: \(currentJitsiURL)
        Socket URL: \(currentSocketURL)
        """
    }
    
    // MARK: - Debug Methods
    func debugCurrentState() {
        print("🔍 EnvironmentManager Debug State:")
        print("   Current Environment: \(currentEnvironment.displayName)")
        print("   UserDefaults API_ENVIRONMENT: \(UserDefaults.standard.string(forKey: "API_ENVIRONMENT") ?? "nil")")
        print("   API URL: \(currentAPIURL)")
        print("   Jitsi URL: \(currentJitsiURL)")
        print("   Socket URL: \(currentSocketURL)")
        print("   Custom API URL: \(customAPIURL)")
        print("   Custom Jitsi URL: \(customJitsiURL)")
        print("   Custom Socket URL: \(customSocketURL)")
    }
    
    // MARK: - Force Refresh
    func forceRefreshAllComponents() {
        print("🔄 Force refreshing all components with new environment...")
        
        // Update URLs first
        updateURLs()
        updateSettingsDisplay()
        
        // Post notification to all components
        NotificationCenter.default.post(
            name: .environmentChanged,
            object: nil,
            userInfo: [
                "environment": currentEnvironment,
                "apiURL": currentAPIURL,
                "jitsiURL": currentJitsiURL,
                "socketURL": currentSocketURL,
                "forceRefresh": true
            ]
        )
        
        // Also post specific notifications for different components
        NotificationCenter.default.post(name: .apiURLChanged, object: nil)
        NotificationCenter.default.post(name: .jitsiURLChanged, object: nil)
        NotificationCenter.default.post(name: .socketURLChanged, object: nil)
        
        print("✅ All components notified of environment change")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let environmentChanged = Notification.Name("EnvironmentManager.environmentChanged")
    static let apiURLChanged = Notification.Name("EnvironmentManager.apiURLChanged")
    static let jitsiURLChanged = Notification.Name("EnvironmentManager.jitsiURLChanged")
    static let socketURLChanged = Notification.Name("EnvironmentManager.socketURLChanged")
}
