package jp.co.pendako.siop.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import jp.co.pendako.siop.RsaPublicJwk
import jp.co.pendako.siop.SiopIdentity

sealed interface EditorMode {
    data class Create(val clientId: String) : EditorMode
    data class Inspect(val identity: SiopIdentity) : EditorMode
}

/**
 * Creating an identity, or inspecting, renaming and deleting one.
 *
 * Only the names can be edited. The subject is derived from the key, so it is
 * shown but never offered as a field: a different key would be a different
 * identity.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdentityEditor(
    session: AuthenticationSession,
    mode: EditorMode,
    onDismiss: () -> Unit,
    onCreate: (SiopIdentity) -> Unit = {},
) {
    val inspected = (mode as? EditorMode.Inspect)?.identity
    val clientId = when (mode) {
        is EditorMode.Create -> mode.clientId
        is EditorMode.Inspect -> mode.identity.clientId
    }
    var label by rememberSaveable { mutableStateOf(inspected?.label ?: "") }
    var note by rememberSaveable { mutableStateOf(inspected?.note ?: "") }
    var confirmsDeletion by remember { mutableStateOf(false) }
    val trimmedLabel = label.trim()

    fun save() {
        val trimmedNote = note.trim()
        if (inspected != null) {
            session.relabel(inspected, trimmedLabel, trimmedNote)
            onDismiss()
        } else {
            session.createIdentity(clientId, trimmedLabel, trimmedNote)?.let {
                onCreate(it)
                onDismiss()
            }
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = {
                            Text(stringResource(if (inspected == null) R.string.create_identity else R.string.identity_details))
                        },
                        navigationIcon = {
                            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                        },
                        actions = {
                            TextButton(
                                onClick = ::save,
                                enabled = trimmedLabel.isNotEmpty(),
                                modifier = Modifier.testTag("save-identity"),
                            ) {
                                Text(stringResource(if (inspected == null) R.string.create else R.string.save))
                            }
                        },
                    )
                },
            ) { padding ->
                Column(
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    OutlinedTextField(
                        value = label,
                        onValueChange = { label = it },
                        label = { Text(stringResource(R.string.name)) },
                        placeholder = { Text(stringResource(R.string.name_placeholder)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().testTag("identity-label"),
                    )
                    OutlinedTextField(
                        value = note,
                        onValueChange = { note = it },
                        label = { Text(stringResource(R.string.note)) },
                        placeholder = { Text(stringResource(R.string.note_placeholder)) },
                        minLines = 2,
                        maxLines = 5,
                        modifier = Modifier.fillMaxWidth().testTag("identity-note"),
                    )
                    if (inspected != null) {
                        Details(session, inspected, onDelete = { confirmsDeletion = true })
                    } else {
                        Section(
                            header = stringResource(R.string.created_for_rp),
                            footer = stringResource(R.string.creates_key_footer),
                        ) {
                            SelectionContainer {
                                Text(clientId, style = MaterialTheme.typography.bodySmall.mono())
                            }
                        }
                    }
                }
            }
        }
    }

    if (confirmsDeletion && inspected != null) {
        val subject = session.subjectOf(inspected) ?: stringResource(R.string.key_unreadable_paren)
        val consequence = stringResource(R.string.delete_consequence)
        AlertDialog(
            onDismissRequest = { confirmsDeletion = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text("${inspected.displayName}\n$subject\n\n$consequence") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmsDeletion = false
                        session.delete(inspected)
                        onDismiss()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = Palette.danger),
                    modifier = Modifier.testTag("confirm-delete"),
                ) {
                    Text(stringResource(R.string.delete_identity_and_key))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmsDeletion = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun Details(session: AuthenticationSession, identity: SiopIdentity, onDelete: () -> Unit) {
    val jwk = session.publicKeys[identity.id]
    var showsKey by rememberSaveable { mutableStateOf(false) }

    Section(
        header = stringResource(R.string.sub_header),
        footer = stringResource(R.string.only_names_change),
    ) {
        SelectionContainer {
            Text(
                jwk?.thumbprint() ?: stringResource(R.string.key_unreadable_detail),
                style = MaterialTheme.typography.bodySmall.mono(),
            )
        }
    }

    Section(header = stringResource(R.string.rp_it_answers)) {
        SelectionContainer {
            Text(identity.clientId, style = MaterialTheme.typography.bodySmall.mono())
        }
    }

    if (jwk != null) {
        Column {
            TextButton(onClick = { showsKey = !showsKey }) {
                Text(stringResource(R.string.public_key_disclosure))
            }
            if (showsKey) {
                SelectionContainer {
                    Text(explanation(jwk, stringResource(R.string.thumbprint_json)), style = MaterialTheme.typography.labelSmall.mono())
                }
            }
        }
    }

    OutlinedButton(
        onClick = onDelete,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.danger),
        modifier = Modifier.testTag("delete-identity"),
    ) {
        Text(stringResource(R.string.delete_identity_and_key))
    }
}

@Composable
private fun Section(header: String, footer: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(header, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
        if (footer != null) {
            Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun explanation(jwk: RsaPublicJwk, canonicalCaption: String): String = """
    |sub_jwk
    |{
    |  "kty": "${jwk.kty}",
    |  "e": "${jwk.e}",
    |  "n": "${jwk.n}"
    |}
    |
    |$canonicalCaption
    |${jwk.canonicalJson}
    |
    |SHA-256 → Base64url
    |${jwk.thumbprint()}
""".trimMargin()
