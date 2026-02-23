import Foundation

enum DefaultFilenames {
    static func backupZipName(now: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd_HHmm"
        return "NotesBackup_\(fmt.string(from: now)).zip"
    }
}

