//
//  AppConstants.swift
//  CosmeticTechMobile
//

import Foundation

enum AppConstants {
    static let appName = "Cosmetic Cloud Dr"
    static let defaultEnvironmentInfo = APIConfiguration.shared.getCurrentEnvironmentInfo()
}

// MARK: - Global Date Format Helpers
extension String {
    /// Parses the receiver as a server date in format "yyyy-MM-dd HH:mm:ss" (UTC) and
    /// returns a human-friendly string in format "MMMM d, yyyy h:mm a" (e.g., August 3, 2025 5:30 PM).
    /// If parsing fails, the original string is returned.
    func asDisplayDateFromServer() -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone(secondsFromGMT: 0)
        inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let date = inFmt.date(from: self) else { return self }

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.dateFormat = "MMMM d, yyyy h:mm a"
        return outFmt.string(from: date)
    }
    
    /// Parses the receiver as a server date and returns a professional relative time string.
    /// Format: "5mins ago", "1 week", "Aug 12, 2025" (if more than 2 weeks)
    /// If parsing fails, the original string is returned.
    func asRelativeTimeFromServer() -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone(secondsFromGMT: 0)
        inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let date = inFmt.date(from: self) else { return self }
        
        return date.asRelativeTimeString()
    }
}

extension Date {
    /// Formats a `Date` into display format "MMMM d, yyyy h:mm a".
    func asDisplayString() -> String {
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.dateFormat = "MMMM d, yyyy h:mm a"
        return outFmt.string(from: self)
    }
    
    /// Returns a professional relative time string.
    /// Format: "5mins ago", "1 week", "Aug 12, 2025" (if more than 2 weeks)
    func asRelativeTimeString() -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        // If the date is in the future, show the absolute date
        if timeInterval < 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: self)
        }
        
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        let weeks = Int(timeInterval / 604800)
        
        switch timeInterval {
        case 0..<60:
            return "just now"
        case 60..<3600:
            return "\(minutes) minutes ago"
        case 3600..<86400:
            if hours == 1 {
                return "1 hour ago"
            } else {
                return "\(hours) hours ago"
            }
        case 86400..<604800:
            if days == 1 {
                return "1 day ago"
            } else {
                return "\(days) days ago"
            }
        case 604800..<1209600: // 1-2 weeks
            return "1 week ago"
        case 1209600..<1814400: // 2-3 weeks
            return "2 weeks ago"
        default:
            // More than 2 weeks - show absolute date in "Aug 12, 2025" format
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: self)
        }
    }
}

// MARK: - Notification Names
extension NSNotification.Name {
    static let voipTokenUpdated = NSNotification.Name("voipTokenUpdated")
    static let jitsiConferenceTerminated = NSNotification.Name("jitsiConferenceTerminated")
}