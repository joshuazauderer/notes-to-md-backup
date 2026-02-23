import CryptoKit
import Foundation

enum StableHash {
    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func shortHex(_ input: String, length: Int = 8) -> String {
        let hex = sha256Hex(input)
        return String(hex.prefix(max(1, length)))
    }
}

