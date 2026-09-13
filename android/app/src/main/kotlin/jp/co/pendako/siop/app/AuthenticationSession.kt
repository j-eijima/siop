package jp.co.pendako.siop.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import jp.co.pendako.siop.AuthenticationErrorResponse
import jp.co.pendako.siop.AuthorizationRequest
import jp.co.pendako.siop.RsaPublicJwk
import jp.co.pendako.siop.SelfIssuedOp
import jp.co.pendako.siop.SiopIdentity
import jp.co.pendako.siop.SiopIdentityStore

/**
 * Drives one authentication request from arrival through consent to the
 * response handed back to the RP (OpenID Connect Core 1.0 Sections 7.3-7.4),
 * and keeps the identities the user answers as.
 */
class AuthenticationSession(private val store: SiopIdentityStore) {

    sealed interface Phase {
        data object Idle : Phase
        data class Consent(val request: AuthorizationRequest) : Phase
        data class Sent(val clientId: String, val redirectUrl: String) : Phase
        data class Declined(val clientId: String) : Phase
        /** The response was built but could not be delivered to the RP. */
        data class Undeliverable(val clientId: String, val redirectUrl: String) : Phase
        data class Failed(val failure: Failure) : Phase
    }

    var phase: Phase by mutableStateOf(Phase.Idle)
        private set

    /** Every identity on the device, in the order they are offered. */
    var identities: List<SiopIdentity> by mutableStateOf(emptyList())
        private set

    /**
     * The public key of each identity whose key could be read, by identity id.
     * An identity missing from here is still listed, but cannot answer.
     */
    var publicKeys: Map<String, RsaPublicJwk> by mutableStateOf(emptyMap())
        private set

    /** An identity operation that failed, to be shown and then cleared. */
    var problem: Failure? by mutableStateOf(null)

    init {
        refresh()
    }

    // Identities

    /** The identities that may answer [clientId], in the order to offer them. */
    fun identitiesFor(clientId: String): List<SiopIdentity> = identities.filter { it.clientId == clientId }

    fun subjectOf(identity: SiopIdentity): String? = publicKeys[identity.id]?.thumbprint()

    /** Makes a key, so only ever at the user's explicit request. */
    fun createIdentity(clientId: String, label: String, note: String): SiopIdentity? = try {
        store.createIdentity(clientId, label, note).also { refresh() }
    } catch (cause: Exception) {
        problem = Failure.CouldNotCreate(Failure.of(cause))
        null
    }

    fun relabel(identity: SiopIdentity, label: String, note: String) {
        try {
            store.relabel(current(identity), label, note)
            refresh()
        } catch (cause: Exception) {
            problem = Failure.CouldNotSave(Failure.of(cause))
        }
    }

    fun delete(identity: SiopIdentity) {
        try {
            store.delete(current(identity))
            refresh()
        } catch (cause: Exception) {
            problem = Failure.CouldNotDelete(Failure.of(cause))
        }
    }

    /**
     * The record as it stands now. A screen can hold one from before a rename,
     * and saving from that would put the old names back.
     */
    private fun current(identity: SiopIdentity): SiopIdentity =
        identities.firstOrNull { it.id == identity.id } ?: identity

    private fun refresh() {
        try {
            reload()
        } catch (cause: Exception) {
            problem = Failure.CouldNotLoad(Failure.of(cause))
        }
    }

    /**
     * Reads every identity and the public key behind each. An identity whose
     * key cannot be read is kept without one, so it is shown as unusable.
     */
    private fun reload() {
        val all = store.allIdentities()
        identities = all
        publicKeys = all.mapNotNull { identity ->
            runCatching { store.publicJwk(identity) }.getOrNull()?.let { identity.id to it }
        }.toMap()
    }

    // Request handling

    fun receive(url: String) {
        val request = try {
            AuthorizationRequest.parse(url)
        } catch (cause: Exception) {
            phase = Phase.Failed(Failure.of(cause))
            return
        }
        try {
            // Takes over the key the key-per-RP version made for this RP, if
            // there is one, so it is offered. Creates no key: nobody has
            // answered anything yet.
            store.identitiesFor(request.clientId)
            reload()
        } catch (cause: Exception) {
            // Fail closed. Carrying on would show an RP this device has
            // answered as a new one, and answering it would make a new key —
            // a different subject, and to the RP a different person.
            phase = Phase.Failed(Failure.CouldNotLoad(Failure.of(cause)))
            return
        }
        phase = Phase.Consent(request)
    }

    /**
     * Signs as [identity], or — when there is none to sign as — as a new
     * identity for this RP, made now because the user has just said to answer
     * (docs/decisions/0004). Hands the response to [deliver], which reports
     * whether the redirect URI could actually be opened.
     */
    fun approve(request: AuthorizationRequest, identity: SiopIdentity?, deliver: (String) -> Boolean) {
        if (identity != null && identity.clientId != request.clientId) {
            // Two RPs answered by one identity would be handed one subject.
            phase = Phase.Failed(Failure.AnswersOnly(identity.clientId))
            return
        }
        if (identity == null && identitiesFor(request.clientId).isNotEmpty()) {
            // A new identity is made only for an RP that has none. One whose
            // identity exists but cannot sign right now gets no stand-in:
            // that would answer as someone else.
            phase = Phase.Failed(Failure.NoStandIn)
            return
        }
        val redirectUrl = try {
            val signer = identity?.let(::current) ?: store.createIdentity(request.clientId)
            val response = SelfIssuedOp.respond(request, store.keyProvider(signer))
            runCatching { store.markUsed(signer) }
            refresh()
            response.redirectUrl
        } catch (cause: Exception) {
            phase = Phase.Failed(Failure.of(cause))
            return
        }
        // Section 7.2 lets client_id name any scheme, including one no
        // installed app handles, so failing to reach the RP is an outcome to
        // report, not an impossible one.
        phase = if (deliver(redirectUrl)) {
            Phase.Sent(request.clientId, redirectUrl)
        } else {
            Phase.Undeliverable(request.clientId, redirectUrl)
        }
    }

    /** Section 3.1.2.6: tell the RP the user declined rather than leaving it waiting. */
    fun decline(request: AuthorizationRequest, deliver: (String) -> Boolean) {
        val redirectUrl = AuthenticationErrorResponse(request).redirectUrl
        phase = if (deliver(redirectUrl)) {
            Phase.Declined(request.clientId)
        } else {
            Phase.Undeliverable(request.clientId, redirectUrl)
        }
    }

    fun reset() {
        phase = Phase.Idle
    }
}
