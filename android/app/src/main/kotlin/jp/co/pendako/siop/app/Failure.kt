package jp.co.pendako.siop.app

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalResources
import jp.co.pendako.siop.SiopError

/**
 * Why something failed. The session says what went wrong; the screen puts it
 * into the user's language. The reasons siopkit gives are protocol detail —
 * "nonce is required" — and stay as they are.
 */
sealed interface Failure {
    data class InvalidRequest(val reason: String) : Failure
    data class UnsupportedResponseType(val responseType: String) : Failure
    data object InvalidScope : Failure
    data class InvalidKey(val reason: String) : Failure
    data class InvalidToken(val reason: String) : Failure
    data class Storage(val reason: String) : Failure
    data object UnreadableRecord : Failure
    data class Unexpected(val description: String) : Failure

    /** An identity asked to answer an RP other than its own. */
    data class AnswersOnly(val clientId: String) : Failure

    /** The RP's identity cannot sign, and no other is made in its place. */
    data object NoStandIn : Failure

    data class CouldNotLoad(val cause: Failure) : Failure
    data class CouldNotCreate(val cause: Failure) : Failure
    data class CouldNotSave(val cause: Failure) : Failure
    data class CouldNotDelete(val cause: Failure) : Failure

    companion object {
        fun of(cause: Throwable): Failure = when (cause) {
            is SiopError.InvalidRequest -> InvalidRequest(cause.reason)
            is SiopError.UnsupportedResponseType -> UnsupportedResponseType(cause.responseType)
            is SiopError.InvalidScope -> InvalidScope
            is SiopError.InvalidKey -> InvalidKey(cause.reason)
            is SiopError.InvalidToken -> InvalidToken(cause.reason)
            is SiopError.Storage -> Storage(cause.reason)
            is SiopError.UnreadableRecord -> UnreadableRecord
            else -> Unexpected(cause.toString())
        }
    }
}

@Composable
fun describe(failure: Failure): String = LocalResources.current.describe(failure)

fun Resources.describe(failure: Failure): String = when (failure) {
    is Failure.InvalidRequest -> getString(R.string.failure_invalid_request, failure.reason)
    is Failure.UnsupportedResponseType -> getString(R.string.failure_unsupported_response_type, failure.responseType)
    Failure.InvalidScope -> getString(R.string.failure_invalid_scope)
    is Failure.InvalidKey -> getString(R.string.failure_invalid_key, failure.reason)
    is Failure.InvalidToken -> getString(R.string.failure_invalid_token, failure.reason)
    is Failure.Storage -> getString(R.string.failure_storage, failure.reason)
    Failure.UnreadableRecord -> getString(R.string.failure_unreadable_record)
    is Failure.Unexpected -> failure.description
    is Failure.AnswersOnly -> getString(R.string.failure_answers_only, failure.clientId)
    Failure.NoStandIn -> getString(R.string.failure_no_stand_in)
    is Failure.CouldNotLoad -> getString(R.string.failure_could_not_load, describe(failure.cause))
    is Failure.CouldNotCreate -> getString(R.string.failure_could_not_create, describe(failure.cause))
    is Failure.CouldNotSave -> getString(R.string.failure_could_not_save, describe(failure.cause))
    is Failure.CouldNotDelete -> getString(R.string.failure_could_not_delete, describe(failure.cause))
}
