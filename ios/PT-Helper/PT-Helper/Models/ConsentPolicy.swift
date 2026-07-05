import Foundation

enum ConsentPolicy {
    /// True when the stored ToS version is missing or older than current.
    static func needsLegalReacceptance(recordedVersion: String?,
                                       currentVersion: String = LegalContent.tosVersion) -> Bool {
        recordedVersion != currentVersion
    }
}

enum AgePolicy {
    static let minimumAge = 13
    static func age(from dateOfBirth: Date, on date: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
    }
    static func isBlocked(dateOfBirth: Date, on date: Date = Date()) -> Bool {
        age(from: dateOfBirth, on: date) < minimumAge
    }
    static func isMinor(dateOfBirth: Date, on date: Date = Date()) -> Bool {
        let a = age(from: dateOfBirth, on: date)
        return a >= minimumAge && a < 18
    }
}
