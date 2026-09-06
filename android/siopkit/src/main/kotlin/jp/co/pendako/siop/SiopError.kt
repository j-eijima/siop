package jp.co.pendako.siop

sealed class SiopError(message: String) : Exception(message) {
    class InvalidRequest(val reason: String) : SiopError("invalid request: $reason")
    class UnsupportedResponseType(val responseType: String) :
        SiopError("unsupported response_type: $responseType")
    class InvalidScope : SiopError("scope must contain openid")
    class InvalidKey(val reason: String) : SiopError("invalid key: $reason")
    class InvalidToken(val reason: String) : SiopError("invalid token: $reason")
}
