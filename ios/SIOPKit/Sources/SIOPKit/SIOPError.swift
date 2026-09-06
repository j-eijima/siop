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
}
