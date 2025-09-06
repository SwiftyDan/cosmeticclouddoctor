//
//  NetworkService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import UIKit
import os.log

// MARK: - Network Error Enum
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError
    case unauthorized
    case forbidden
    case validationError(String)
    case serverError(String)
    case requestCancelled
    case noInternetConnection
    case timeoutError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to decode response"
        case .unauthorized:
            return "Unauthorized access"
        case .forbidden:
            return "Access forbidden"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .requestCancelled:
            return "Request was cancelled"
        case .noInternetConnection:
            return "No internet connection available"
        case .timeoutError:
            return "Request timed out"
        }
    }
}

// MARK: - HTTP Method Enum
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

// MARK: - Request Configuration
struct RequestConfiguration {
    let timeoutInterval: TimeInterval
    let retryCount: Int
    let retryDelay: TimeInterval
    let enableLogging: Bool
    let cachePolicy: URLRequest.CachePolicy
    
    static let `default` = RequestConfiguration(
        timeoutInterval: 30.0,
        retryCount: 2,
        retryDelay: 1.0,
        enableLogging: true,
        cachePolicy: .reloadIgnoringLocalCacheData
    )
    
    static let aggressive = RequestConfiguration(
        timeoutInterval: 15.0,
        retryCount: 3,
        retryDelay: 0.5,
        enableLogging: true,
        cachePolicy: .reloadIgnoringLocalCacheData
    )
    
    static let conservative = RequestConfiguration(
        timeoutInterval: 60.0,
        retryCount: 1,
        retryDelay: 2.0,
        enableLogging: false,
        cachePolicy: .returnCacheDataElseLoad
    )
}

// MARK: - Network Service Protocol
protocol NetworkServiceProtocol {
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]?,
        headers: [String: String]?,
        configuration: RequestConfiguration?,
        responseType: T.Type
    ) async throws -> T
    
    func request<T: Codable>(
        request: URLRequest,
        configuration: RequestConfiguration?,
        responseType: T.Type
    ) async throws -> T
    
    func cancelAllRequests()
}

// MARK: - Network Service Implementation
class NetworkService: NetworkServiceProtocol {
    private let baseURL: String
    private let session: URLSession
    private let logger = Logger(subsystem: "com.cosmetictech.network", category: "NetworkService")
    private var activeTasks: Set<URLSessionTask> = []
    private let taskQueue = DispatchQueue(label: "com.cosmetictech.network.tasks", attributes: .concurrent)
    
    init(baseURL: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        
        // Configure URLSession for optimal performance on older devices
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.waitsForConnectivity = true       // Wait for connectivity on older devices
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = session ?? URLSession(configuration: configuration)
    }
    
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        
        let config = configuration ?? .default
        
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeoutInterval
        request.cachePolicy = config.cachePolicy
        
        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add body for POST/PUT/PATCH requests
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw NetworkError.networkError(error)
            }
        }
        
        // Log request if enabled
        if config.enableLogging {
            logRequest(request, body: body)
        }
        
        // Check network reachability before making request
        guard await Reachability.isConnectedToNetwork() else {
            throw NetworkError.noInternetConnection
        }
        
        return try await performRequestWithRetry(
            request: request,
            configuration: config,
            responseType: responseType
        )
    }
    
    func request<T: Codable>(
        request: URLRequest,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        
        let config = configuration ?? .default
        
        // Log request if enabled
        if config.enableLogging {
            logRequest(request, body: nil)
        }
        
        // Check network reachability before making request
        guard await Reachability.isConnectedToNetwork() else {
            throw NetworkError.noInternetConnection
        }
        
        return try await performRequestWithRetry(
            request: request,
            configuration: config,
            responseType: responseType
        )
    }
    
    func cancelAllRequests() {
        taskQueue.async(flags: .barrier) {
            self.activeTasks.forEach { $0.cancel() }
            self.activeTasks.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private func performRequestWithRetry<T: Codable>(
        request: URLRequest,
        configuration: RequestConfiguration,
        responseType: T.Type
    ) async throws -> T {
        
        var lastError: Error?
        
        for attempt in 0...configuration.retryCount {
            do {
                return try await performSingleRequest(
                    request: request,
                    responseType: responseType
                )
            } catch {
                lastError = error
                
                // Don't retry on certain errors
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .unauthorized, .forbidden, .validationError, .requestCancelled:
                        throw networkError
                    default:
                        break
                    }
                }
                
                // If this is not the last attempt, wait before retrying
                if attempt < configuration.retryCount {
                    if configuration.enableLogging {
                        logger.warning("Request failed, retrying in \(configuration.retryDelay)s (attempt \(attempt + 1)/\(configuration.retryCount + 1))")
                    }
                    try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                }
            }
        }
        
        // All attempts failed
        throw lastError ?? NetworkError.serverError("Request failed after \(configuration.retryCount + 1) attempts")
    }
    
    private func performSingleRequest<T: Codable>(
        request: URLRequest,
        responseType: T.Type
    ) async throws -> T {
        
        let task = session.dataTask(with: request) { _, _, _ in }
        
        // Track active task
        taskQueue.async(flags: .barrier) {
            self.activeTasks.insert(task)
        }
        
        defer {
            taskQueue.async(flags: .barrier) {
                self.activeTasks.remove(task)
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.networkError(NSError(domain: "NetworkError", code: -1, userInfo: nil))
            }
            
            // Log response if enabled
            logResponse(httpResponse, data: data)
            
            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                // Trigger automatic logout for unauthorized response
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("UnauthorizedResponse"), object: nil)
                }
                throw NetworkError.unauthorized
            case 403:
                // Trigger automatic logout for forbidden response
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("UnauthorizedResponse"), object: nil)
                }
                throw NetworkError.forbidden
            case 422:
                // Handle validation errors specifically
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    throw NetworkError.validationError(errorResponse.message)
                } else {
                    throw NetworkError.validationError("Validation failed")
                }
            case 400...499:
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    throw NetworkError.serverError(errorResponse.message)
                } else {
                    throw NetworkError.serverError("Client error: \(httpResponse.statusCode)")
                }
            case 500...599:
                throw NetworkError.serverError("Server error: \(httpResponse.statusCode)")
            default:
                throw NetworkError.serverError("Unknown error: \(httpResponse.statusCode)")
            }
            
            // Decode response
            do {
                let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                return decodedResponse
            } catch {
                logger.error("Failed to decode response: \(error.localizedDescription)")
                throw NetworkError.decodingError
            }
            
        } catch {
            // Handle specific timeout errors
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw NetworkError.timeoutError
                case .notConnectedToInternet:
                    throw NetworkError.noInternetConnection
                case .cannotConnectToHost:
                    throw NetworkError.serverError("Cannot connect to server. Please try again later.")
                case .cancelled:
                    throw NetworkError.requestCancelled
                default:
                    throw NetworkError.networkError(urlError)
                }
            }
            
            if let networkError = error as? NetworkError {
                throw networkError
            } else {
                throw NetworkError.networkError(error)
            }
        }
    }
    
    private func logRequest(_ request: URLRequest, body: [String: Any]?) {
        logger.info("🌐 \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "NO_URL")")
        
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            logger.debug("📋 Headers: \(headers)")
        }
        
        if let body = body {
            logger.debug("📦 Body: \(body)")
        }
    }
    
    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        let statusEmoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        logger.info("\(statusEmoji) Response: \(response.statusCode) - \(response.url?.absoluteString ?? "NO_URL")")
        
        if let responseData = String(data: data, encoding: .utf8), !responseData.isEmpty {
            logger.debug("📥 Response Data: \(responseData)")
        }
    }
}

// MARK: - Error Response
struct ErrorResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Network Reachability Helper
class Reachability {
    static func isConnectedToNetwork() async -> Bool {
        // Use async/await instead of semaphore to avoid blocking
        return await withCheckedContinuation { continuation in
            guard let url = URL(string: "https://www.apple.com") else {
                continuation.resume(returning: false)
                return
            }
            
            let task = URLSession.shared.dataTask(with: url) { _, response, error in
                let isConnected = (response as? HTTPURLResponse)?.statusCode == 200 && error == nil
                continuation.resume(returning: isConnected)
            }
            
            task.resume()
        }
    }
    
    static func isConnectedToNetworkSync() -> Bool {
        guard let url = URL(string: "https://www.apple.com") else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var isConnected = false
        
        let task = URLSession.shared.dataTask(with: url) { _, response, error in
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200 && error == nil
            semaphore.signal()
        }
        
        task.resume()
        semaphore.wait()
        
        return isConnected
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable {
    // This struct can be used for endpoints that return empty or minimal responses
    let success: Bool?
    let message: String?
    
    init() {
        self.success = nil
        self.message = nil
    }
}

// MARK: - Network Service Extensions
extension NetworkService {
    /// Convenience method for GET requests
    func get<T: Codable>(
        endpoint: String,
        headers: [String: String]? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            headers: headers,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for POST requests
    func post<T: Codable>(
        endpoint: String,
        body: [String: Any]?,
        headers: [String: String]? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .POST,
            body: body,
            headers: headers,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for PUT requests
    func put<T: Codable>(
        endpoint: String,
        body: [String: Any]?,
        headers: [String: String]? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .PUT,
            body: body,
            headers: headers,
            configuration: configuration,
            responseType: responseType
        )
    }
    
    /// Convenience method for DELETE requests
    func delete<T: Codable>(
        endpoint: String,
        headers: [String: String]? = nil,
        configuration: RequestConfiguration? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await request(
            endpoint: endpoint,
            method: .DELETE,
            body: nil,
            headers: headers,
            configuration: configuration,
            responseType: responseType
        )
    }
} 
