package jp.co.pendako.siop.app

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.net.URI
import jp.co.pendako.siop.SiopIdentity

/**
 * The UI mock's palette. Blue marks a value copied from the request, green a
 * value that comes from the chosen key; everything fixed or decided at signing
 * stays grey. Switching identities changes exactly the green rows.
 */
object Palette {
    val request: Color @Composable get() = pick(light = 0xFF376BAF, dark = 0xFF8FB3EA)
    val key: Color @Composable get() = pick(light = 0xFF24664A, dark = 0xFF7FC4A0)
    val danger: Color @Composable get() = pick(light = 0xFFAF4540, dark = 0xFFF09A94)
    val caution: Color @Composable get() = pick(light = 0xFFB0660A, dark = 0xFFF0B060)

    @Composable
    private fun pick(light: Long, dark: Long) = Color(if (isSystemInDarkTheme()) dark else light)
}

@Composable
fun SiopTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Color(0xFF7FC4A0), onPrimary = Color(0xFF0B2A1C), error = Color(0xFFF09A94))
    } else {
        lightColorScheme(primary = Color(0xFF24664A), onPrimary = Color.White, error = Color(0xFFAF4540))
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Where a value in the response comes from. */
enum class ValueSource { Request, Key, Fixed }

@Composable
private fun ValueSource?.color(): Color = when (this) {
    ValueSource.Request -> Palette.request
    ValueSource.Key -> Palette.key
    ValueSource.Fixed, null -> MaterialTheme.colorScheme.onSurfaceVariant
}

/** Protocol values are shown in a fixed-width face, exactly as they travel. */
fun TextStyle.mono(): TextStyle = copy(fontFamily = FontFamily.Monospace)

@Composable
fun SourceBadge(text: String, source: ValueSource? = null) {
    val color = source.color()
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        color = color,
        maxLines = 1,
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}

/** What the three colours mean, shown beside the preview they colour. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SourceLegend() {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SourceBadge(stringResource(R.string.origin_copied), ValueSource.Request)
        SourceBadge(stringResource(R.string.legend_key), ValueSource.Key)
        SourceBadge(stringResource(R.string.legend_fixed), ValueSource.Fixed)
    }
}

/** A card with a numbered heading, as the mock lays out each step. */
@Composable
fun Panel(
    title: String,
    number: String? = null,
    subtitle: String? = null,
    badge: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(14.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            if (number != null) {
                Text(
                    number,
                    style = MaterialTheme.typography.labelMedium.mono(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                if (subtitle != null) {
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            badge?.invoke()
        }
        content()
    }
}

/** One request parameter, name above the value exactly as it arrived. */
@Composable
fun ParameterRow(name: String, value: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            name,
            style = MaterialTheme.typography.labelSmall.mono(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SelectionContainer {
            Text(value ?: stringResource(R.string.no_value), style = MaterialTheme.typography.bodySmall.mono())
        }
    }
}

/**
 * One value of the response, with where it comes from.
 *
 * The value is its own text rather than merged with its name, so that it
 * reads — and can be copied — exactly as it will be signed. A protocol value
 * is never translated.
 *
 * @param value null when the value does not exist yet: a subject made at the
 *   moment the user answers.
 */
@Composable
fun ClaimRow(name: String, value: String?, origin: String, source: ValueSource, maxLines: Int = Int.MAX_VALUE) {
    val shade = if (source == ValueSource.Key) Palette.key.copy(alpha = 0.07f) else Color.Transparent
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(shade, RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(name, style = MaterialTheme.typography.labelMedium.mono().copy(fontWeight = FontWeight.SemiBold))
            Spacer(Modifier.weight(1f).width(8.dp))
            SourceBadge(origin, source)
        }
        if (value != null) {
            SelectionContainer {
                Text(
                    value,
                    style = MaterialTheme.typography.bodySmall.mono(),
                    maxLines = maxLines,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        } else {
            Text(
                stringResource(R.string.created_on_answer),
                style = MaterialTheme.typography.bodySmall.copy(fontStyle = FontStyle.Italic),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * An identity as a row: its name, its note, and its subject cut to fit.
 *
 * @param subject null when the key could not be read, which leaves the
 *   identity unable to answer. It is still listed, so the user can see it and
 *   delete it.
 * @param selected null when the row is not something to choose between.
 */
@Composable
fun IdentityRow(identity: SiopIdentity, subject: String?, selected: Boolean? = null) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(Palette.key.copy(alpha = 0.14f), CircleShape)
                .clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            Text(identity.displayName.take(1), style = MaterialTheme.typography.titleMedium, color = Palette.key)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(identity.displayName, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
            Text(
                identity.note.ifEmpty { stringResource(R.string.identity_for_rp) },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (subject != null) {
                Text(
                    "sub $subject",
                    style = MaterialTheme.typography.labelSmall.mono(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
            } else {
                Text(
                    stringResource(R.string.key_unreadable_row),
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.danger,
                )
            }
        }
        if (selected != null) {
            RadioButton(
                selected = selected,
                onClick = null,
                colors = RadioButtonDefaults.colors(selectedColor = Palette.key),
            )
        }
    }
}

/**
 * What to call the identity on screen. One made by answering an RP for the
 * first time, or taken over from the key-per-RP version, has not been named,
 * so it goes by the RP it answers — by host where the RP is a web address, and
 * whole otherwise, since a custom scheme's "host" is whatever follows `://`
 * and names nothing.
 */
val SiopIdentity.displayName: String
    get() {
        if (label.isNotEmpty()) return label
        val uri = runCatching { URI(clientId) }.getOrNull()
        val host = uri?.host
        return if (uri?.scheme in setOf("http", "https") && !host.isNullOrEmpty()) host else clientId
    }
