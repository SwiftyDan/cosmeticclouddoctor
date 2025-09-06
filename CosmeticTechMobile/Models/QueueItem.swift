//
//  QueueItem.swift
//  CosmeticTechMobile
//
//  Domain model for realtime queue items.
//

import Foundation

/// Represents a single item in the realtime queue.
struct QueueItem: Identifiable, Equatable, Codable {
    let id: String
    let patientName: String
    let clinic: String
    let createdAt: Date
    // Extra metadata used for callbacks
    let clinicSlug: String?
    let scriptId: Int?
    let scriptUUID: String?
    let scriptNumber: String?
    let roomName: String?
    
    // Custom initializer for preserving timestamps
    init(id: String, patientName: String, clinic: String, createdAt: Date, clinicSlug: String?, scriptId: Int?, scriptUUID: String?, scriptNumber: String?, roomName: String?) {
        self.id = id
        self.patientName = patientName
        self.clinic = clinic
        self.createdAt = createdAt
        self.clinicSlug = clinicSlug
        self.scriptId = scriptId
        self.scriptUUID = scriptUUID
        self.scriptNumber = scriptNumber
        self.roomName = roomName
    }

    /// Attempts to create a `QueueItem` from a generic dictionary payload.
    /// Supports multiple key variants from the backend payload.
    static func fromDictionary(_ dict: [String: Any]) -> QueueItem? {
        guard let id = dict["id"] as? String ?? dict["uuid"] as? String else { return nil }
        let patient = dict["patient_name"] as? String ?? dict["name"] as? String ?? "Unknown"
        let clinic = dict["clinic"] as? String ?? dict["clinic_slug"] as? String ?? ""
        let createdAtStr = dict["created_at"] as? String
        let created: Date
        if let s = createdAtStr {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            created = fmt.date(from: s) ?? Date()
        } else {
            created = Date()
        }
        let clinicSlug = dict["clinic_slug"] as? String
        let scriptId = (dict["script_id"] as? Int) ?? Int((dict["script_id"] as? String) ?? "")
        let scriptUUID = dict["script_uuid"] as? String
        return QueueItem(id: id, patientName: patient, clinic: clinic, createdAt: created, clinicSlug: clinicSlug, scriptId: scriptId, scriptUUID: scriptUUID, scriptNumber: dict["script_number"] as? String, roomName: dict["room_name"] as? String)
    }

    /// Builds a `QueueItem` from the expected broadcast payload shape shown by backend:
    /// { action, doctor_user_id, clinic_slug, script_id, clinic_name, caller_name, script_uuid, timestamp }
    static func fromBroadcastPayload(_ dict: [String: Any]) -> QueueItem? {
        // Choose a stable identifier from script_uuid if available, otherwise from script_id
        if let uuid = dict["script_uuid"] as? String, !uuid.isEmpty {
            let name = (dict["caller_name"] as? String) ?? "Unknown"
            let clinic = (dict["clinic_name"] as? String) ?? (dict["clinic_slug"] as? String) ?? ""
            let ts = (dict["timestamp"] as? Double) ?? Double(dict["timestamp"] as? Int ?? 0)
            let created = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
            // Handle both string and integer script_id types from WebSocket
            let scriptId = (dict["script_id"] as? Int) ?? Int((dict["script_id"] as? String) ?? "")
            return QueueItem(id: uuid, patientName: name, clinic: clinic, createdAt: created, clinicSlug: (dict["clinic_slug"] as? String), scriptId: scriptId, scriptUUID: uuid, scriptNumber: dict["script_number"] as? String, roomName: dict["room_name"] as? String)
        }
        // Handle both string and integer script_id types from WebSocket
        if let scriptId = (dict["script_id"] as? Int) ?? Int((dict["script_id"] as? String) ?? "") {
            let name = (dict["caller_name"] as? String) ?? "Unknown"
            let clinic = (dict["clinic_name"] as? String) ?? (dict["clinic_slug"] as? String) ?? ""
            let ts = (dict["timestamp"] as? Double) ?? Double(dict["timestamp"] as? Int ?? 0)
            let created = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
            return QueueItem(id: "script_\(scriptId)", patientName: name, clinic: clinic, createdAt: created, clinicSlug: (dict["clinic_slug"] as? String), scriptId: scriptId, scriptUUID: dict["script_uuid"] as? String, scriptNumber: dict["script_number"] as? String, roomName: dict["room_name"] as? String)
        }
        return nil
    }
}


