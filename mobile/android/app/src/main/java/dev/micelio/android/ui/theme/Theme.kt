package dev.micelio.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = MicelioLeaf,
    onPrimary = MicelioSand,
    secondary = MicelioGreen,
    onSecondary = MicelioSand
)

private val LightColorScheme = lightColorScheme(
    primary = MicelioGreen,
    onPrimary = MicelioSand,
    secondary = MicelioLeaf,
    onSecondary = MicelioSand
)

@Composable
fun MicelioTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        content = content
    )
}
