import AppKit
import ApplicationServices
import Foundation

enum AutomationPermission {
    /// Attempts to trigger the Automation prompt for controlling Notes.
    /// Returns the OSStatus from `AEDeterminePermissionToAutomateTarget`.
    static func requestNotesPermission(askUserIfNeeded: Bool) -> OSStatus {
        // If Notes isn't running, some systems report procNotFound (-600).
        // Best-effort: launch Notes first to make permission prompts work reliably.
        if !NotesAppLauncher.isNotesRunning() {
            Task { @MainActor in
                try? await NotesAppLauncher.ensureRunning(timeout: 3.0)
            }
        }

        let bundleID = "com.apple.Notes" as CFString
        let data = (bundleID as String).data(using: .utf8)! as CFData

        var target = AEAddressDesc()
        let createStatus = AECreateDesc(
            DescType(typeApplicationBundleID),
            CFDataGetBytePtr(data),
            CFIndex(CFDataGetLength(data)),
            &target
        )
        guard createStatus == noErr else { return OSStatus(createStatus) }
        defer { AEDisposeDesc(&target) }

        // Any event class/id is fine for requesting consent; open is commonly used.
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(kCoreEventClass), AEEventID(kAEOpenApplication), askUserIfNeeded)
    }

    static func describe(_ status: OSStatus) -> String {
        if status == noErr { return "noErr" }
        if status == -1743 { return "errAEEventNotPermitted (-1743)" }
        if let s = SecCopyErrorMessageString(status, nil) as String? {
            return "\(s) (\(status))"
        }
        return "OSStatus(\(status))"
    }
}

