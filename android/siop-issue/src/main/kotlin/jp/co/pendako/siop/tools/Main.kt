package jp.co.pendako.siop.tools

import jp.co.pendako.siop.KeyPairProvider
import jp.co.pendako.siop.SelfIssuedOp
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.system.exitProcess

/**
 * Issues a self-issued ID Token for a request URL and prints the response as
 * JSON, matching the Swift `siop-issue` so that either implementation's output
 * can be fed to the other's verifier.
 *
 *     gradle :siop-issue:run --args="openid://?response_type=id_token&..."
 *
 * Pass --expired to issue an already-expired token.
 */
fun main(arguments: Array<String>) {
    val requestUrl = arguments.firstOrNull { !it.startsWith("--") }
    if (requestUrl == null) {
        System.err.println("usage: siop-issue <openid:// request URL> [--expired]")
        exitProcess(2)
    }
    val now = System.currentTimeMillis() / 1000 - if (arguments.contains("--expired")) 3600 else 0

    try {
        val provider = KeyPairProvider.generate()
        val response = SelfIssuedOp(provider).handle(requestUrl, nowEpochSeconds = now)
        val output = buildJsonObject {
            put("id_token", response.idToken)
            put("redirect_url", response.redirectUrl)
            put("sub", provider.publicJwk().thumbprint())
        }
        println(Json { prettyPrint = true }.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), output))
    } catch (cause: Exception) {
        System.err.println("error: $cause")
        exitProcess(1)
    }
}
