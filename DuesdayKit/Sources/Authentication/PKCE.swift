import CryptoKit
import Foundation

/// RFC 7636 PKCE pair. No client secret ever ships in the app — the code
/// exchange is protected by the verifier instead (ADR-6).
public struct PKCE: Sendable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let challengeMethod = "S256"

    public init() {
        var bytes = [UInt8](repeating: 0, count: 64)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        self.init(verifierBytes: bytes)
    }

    /// Deterministic construction for tests.
    public init(verifierBytes: [UInt8]) {
        let verifier = Data(verifierBytes).base64URLEncodedString()
        self.codeVerifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.codeChallenge = Data(digest).base64URLEncodedString()
    }
}

extension Data {
    /// Base64url without padding (RFC 4648 §5), as OAuth requires.
    public func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url content (padding-tolerant). Gmail bodies use this.
    public init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
