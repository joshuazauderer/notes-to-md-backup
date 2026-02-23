import Foundation

enum ZipUtil {
    static func zipDirectoryContents(sourceDirectory: URL, to destinationZip: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationZip.path) {
            try fileManager.removeItem(at: destinationZip)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDirectory
        process.arguments = ["-r", "-q", destinationZip.path, "."]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw AppError.zipFailed(err.isEmpty ? "zip exited with status \(process.terminationStatus)" : err)
        }
    }
}

