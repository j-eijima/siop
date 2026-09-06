package jp.co.pendako.siop

import java.util.Base64

internal object Base64Url {
    private val encoder: Base64.Encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder: Base64.Decoder = Base64.getUrlDecoder()

    fun encode(bytes: ByteArray): String = encoder.encodeToString(bytes)

    fun decode(value: String): ByteArray = decoder.decode(value)
}
