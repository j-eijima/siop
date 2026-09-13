package jp.co.pendako.siop.app

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.co.pendako.siop.AuthorizationRequest
import jp.co.pendako.siop.RsaPublicJwk
import jp.co.pendako.siop.SelfIssuedIdToken
import jp.co.pendako.siop.SiopIdentity

/**
 * Consent screen for an incoming request, laid out as the UI mock's SIOP
 * view: what arrived, who to answer as, and exactly what will be signed.
 *
 * A Self-Issued OP cannot authenticate the RP, so the redirect URI is shown as
 * it arrived and labelled as unverified rather than dressed up as a trusted
 * identity.
 *
 * @param onApprove answers as the given identity, or as a new one when null.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConsentScreen(
    session: AuthenticationSession,
    request: AuthorizationRequest,
    onApprove: (SiopIdentity?) -> Unit,
    onDecline: () -> Unit,
) {
    var chosenId by rememberSaveable(request) { mutableStateOf<String?>(null) }
    var editor by remember { mutableStateOf<EditorMode?>(null) }

    val candidates = session.identitiesFor(request.clientId)
    // The identity the response will be signed as: the one the user picked, or
    // else the first that can sign. Null means a new one will be made.
    val usable = candidates.filter { session.subjectOf(it) != null }
    val signer = usable.firstOrNull { it.id == chosenId } ?: usable.firstOrNull()
    // This RP has identities but none can sign. A new one is not made in their
    // place, since that would answer as someone else; the user can still
    // create one on purpose.
    val blocked = signer == null && candidates.isNotEmpty()

    Scaffold(
        topBar = { CenterAlignedTopAppBar(title = { Text(stringResource(R.string.consent_title)) }) },
        // The decision stays reachable however long the request is.
        bottomBar = { ActionBar(signer, blocked, onApprove = { onApprove(signer) }, onDecline = onDecline) },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                RequestPanel(request)
                IdentityPanel(
                    session = session,
                    candidates = candidates,
                    signer = signer,
                    onChoose = { chosenId = it.id },
                    onInspect = { editor = EditorMode.Inspect(it) },
                    onCreate = { editor = EditorMode.Create(request.clientId) },
                )
                PreviewPanel(session, request, signer)
                FragmentPanel(request)
            }
        }
    }

    editor?.let { mode ->
        IdentityEditor(session, mode, onDismiss = { editor = null }, onCreate = { chosenId = it.id })
    }
}

// 01 What arrived

@Composable
private fun RequestPanel(request: AuthorizationRequest) {
    Panel(
        title = stringResource(R.string.request_panel_title),
        number = "01",
        badge = { SourceBadge(stringResource(R.string.requester_unverified)) },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(R.string.requester_label),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectionContainer {
                Text(request.clientId, style = MaterialTheme.typography.bodyMedium.mono())
            }
            Text(
                stringResource(R.string.requester_warning),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        HorizontalDivider()
        request.receivedParameters.forEach { (name, value) -> ParameterRow(name, value.ifEmpty { null }) }
    }
}

// Who to answer as

@Composable
private fun IdentityPanel(
    session: AuthenticationSession,
    candidates: List<SiopIdentity>,
    signer: SiopIdentity?,
    onChoose: (SiopIdentity) -> Unit,
    onInspect: (SiopIdentity) -> Unit,
    onCreate: () -> Unit,
) {
    Panel(
        title = stringResource(R.string.identities_header),
        subtitle = stringResource(R.string.identities_panel_subtitle),
        badge = { SourceBadge(pluralStringResource(R.plurals.identity_count, candidates.size, candidates.size)) },
    ) {
        if (candidates.isEmpty()) {
            Text(stringResource(R.string.first_request), style = MaterialTheme.typography.bodyMedium)
        } else {
            candidates.forEach { identity ->
                IdentityChoice(
                    identity = identity,
                    subject = session.subjectOf(identity),
                    isSigner = identity.id == signer?.id,
                    onChoose = { onChoose(identity) },
                    onInspect = { onInspect(identity) },
                )
            }
        }
        OutlinedButton(onClick = onCreate, modifier = Modifier.testTag("create-identity")) {
            Text("+ ")
            Text(stringResource(R.string.create_identity))
        }
        Text(
            stringResource(R.string.names_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun IdentityChoice(
    identity: SiopIdentity,
    subject: String?,
    isSigner: Boolean,
    onChoose: () -> Unit,
    onInspect: () -> Unit,
) {
    val details = stringResource(R.string.details)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .border(
                width = if (isSigner) 2.dp else 1.dp,
                color = if (isSigner) Palette.key else MaterialTheme.colorScheme.outlineVariant,
                shape = RoundedCornerShape(10.dp),
            )
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .weight(1f)
                .selectable(selected = isSigner, enabled = subject != null, role = Role.RadioButton, onClick = onChoose),
        ) {
            IdentityRow(identity, subject, selected = isSigner)
        }
        IconButton(onClick = onInspect, modifier = Modifier.semantics { contentDescription = details }) {
            Text("ⓘ", fontSize = 20.sp, color = MaterialTheme.colorScheme.primary)
        }
    }
}

// 02 What will be signed

@Composable
private fun PreviewPanel(session: AuthenticationSession, request: AuthorizationRequest, signer: SiopIdentity?) {
    var showsWholeKey by rememberSaveable { mutableStateOf(false) }
    val jwk = signer?.let { session.publicKeys[it.id] }
    val minutes = (SelfIssuedIdToken.LIFETIME_SECONDS / 60).toInt()
    val otherScopes = request.scope.filter { it != "openid" }

    Panel(
        title = stringResource(R.string.preview_title),
        number = "02",
        badge = { SourceBadge(stringResource(R.string.not_yet_signed), ValueSource.Key) },
    ) {
        Text(
            if (signer != null) {
                stringResource(R.string.using_identity, signer.displayName)
            } else {
                stringResource(R.string.new_identity_on_answer)
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.token_caption),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            )
            Spacer(Modifier.weight(1f))
            Text(
                "RS256",
                style = MaterialTheme.typography.labelSmall.mono(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        ClaimRow("iss", SelfIssuedIdToken.ISSUER, stringResource(R.string.origin_fixed), ValueSource.Fixed)
        ClaimRow("aud", request.clientId, stringResource(R.string.origin_from_client_id), ValueSource.Request)
        ClaimRow("sub", jwk?.thumbprint(), stringResource(R.string.origin_derived), ValueSource.Key)
        ClaimRow(
            "sub_jwk",
            jwk?.let(::json),
            stringResource(R.string.origin_chosen_key),
            ValueSource.Key,
            maxLines = if (showsWholeKey) Int.MAX_VALUE else 3,
        )
        if (jwk != null) {
            TextButton(onClick = { showsWholeKey = !showsWholeKey }) {
                Text(stringResource(if (showsWholeKey) R.string.collapse_key else R.string.show_whole_key))
            }
        }
        ClaimRow("nonce", request.nonce, stringResource(R.string.origin_from_nonce), ValueSource.Request)
        ClaimRow(
            "iat / exp",
            stringResource(R.string.iat_exp_value, minutes),
            stringResource(R.string.origin_at_signing),
            ValueSource.Fixed,
        )

        SourceLegend()
        Text(
            stringResource(R.string.legend_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (otherScopes.isNotEmpty()) {
            Text(
                stringResource(R.string.other_scopes, otherScopes.joinToString(" ")),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun FragmentPanel(request: AuthorizationRequest) {
    Panel(title = stringResource(R.string.fragment_title)) {
        ClaimRow(
            "state",
            request.state ?: stringResource(R.string.omitted),
            stringResource(R.string.origin_copied),
            ValueSource.Request,
        )
        Text(
            stringResource(R.string.nonce_state_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The public key as it travels in `sub_jwk`. */
private fun json(jwk: RsaPublicJwk): String = """{ "kty": "${jwk.kty}", "e": "${jwk.e}", "n": "${jwk.n}" }"""

// Answer

@Composable
private fun ActionBar(signer: SiopIdentity?, blocked: Boolean, onApprove: () -> Unit, onDecline: () -> Unit) {
    Surface(tonalElevation = 3.dp) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                stringResource(
                    when {
                        blocked -> R.string.action_blocked
                        signer == null -> R.string.action_new
                        else -> R.string.action_chosen
                    }
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = onDecline, modifier = Modifier.testTag("decline")) {
                    Text(stringResource(R.string.decline))
                }
                Button(
                    onClick = onApprove,
                    enabled = !blocked,
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.key),
                    modifier = Modifier.weight(1f).testTag("approve"),
                ) {
                    Text(stringResource(if (signer == null) R.string.use_new_identity else R.string.use_this_identity))
                }
            }
        }
    }
}
