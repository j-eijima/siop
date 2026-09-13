import Foundation

public enum SIOPError: Error, Equatable {
    case invalidRequest(String)
    case unsupportedResponseType(String)
    case invalidScope
    case keyGenerationFailed(String?)
    case signingFailed(String?)
    case derParsingFailed
    case invalidKey
    case invalidToken(String)
    /// The Keychain refused an operation, with the status it gave.
    case keyStore(OSStatus)
    /// A stored identity record does not decode.
    case unreadableRecord
}
