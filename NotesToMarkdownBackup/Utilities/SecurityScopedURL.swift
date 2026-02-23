import Foundation

struct SecurityScopedURL {
    let url: URL
    private var didStartAccessing: Bool = false

    init(url: URL) {
        self.url = url
    }

    mutating func startAccessing() throws {
        didStartAccessing = url.startAccessingSecurityScopedResource()
        if !didStartAccessing {
            // In practice SavePanel URLs usually work without issues, but we keep this explicit.
            throw AppError.fileWriteFailed("Couldn’t access the selected destination (security-scoped access failed).")
        }
    }

    mutating func stopAccessing() {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
        didStartAccessing = false
    }
}

