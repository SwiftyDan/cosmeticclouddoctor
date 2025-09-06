//
//  KeychainService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import Security

// MARK: - Keychain Error
enum KeychainError: Error, LocalizedError {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidItemFormat
    case unexpectedItemData
    case unhandledError(status: OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "Item already exists in keychain"
        case .unknown(let status):
            return "Unknown keychain error: \(status)"
        case .itemNotFound:
            return "Item not found in keychain"
        case .invalidItemFormat:
            return "Invalid item format"
        case .unexpectedItemData:
            return "Unexpected item data"
        case .unhandledError(let status):
            return "Unhandled keychain error: \(status)"
        }
    }
}

// MARK: - Keychain Service Protocol
protocol KeychainServiceProtocol {
    func save<T: Codable>(key: String, value: T) throws
    func retrieve<T: Codable>(key: String, type: T.Type) -> T?
    func delete(key: String)
    func clearAll()
    func getAllKeys() -> [String]
}

// MARK: - Keychain Service Implementation
class KeychainService: KeychainServiceProtocol {
    private let service = "com.cosmeticcloudtech.app"
    
    func save<T: Codable>(key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            
            if updateStatus != errSecSuccess {
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    func retrieve<T: Codable>(key: String, type: T.Type) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            print("Keychain retrieve error: \(status)")
            return nil
        }
        
        guard let data = result as? Data else {
            return nil
        }
        
        do {
            let decodedValue = try JSONDecoder().decode(T.self, from: data)
            return decodedValue
        } catch {
            print("Keychain decode error: \(error)")
            return nil
        }
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain delete error: \(status)")
        }
    }
    
    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain clear all error: \(status)")
        }
    }

    func getAllKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            print("Keychain getAllKeys error: \(status)")
            return []
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            if let account = item[kSecAttrAccount as String] as? String {
                return account
            }
            return nil
        }
    }
} 