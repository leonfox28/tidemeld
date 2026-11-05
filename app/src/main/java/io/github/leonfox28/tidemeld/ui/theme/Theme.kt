package io.github.leonfox28.tidemeld.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import io.github.leonfox28.tidemeld.core.settings.ThemeMode

/** Whether [mode] comes out dark, given the system's own setting. */
@Composable
fun ThemeMode.isDark(): Boolean =
    when (this) {
        ThemeMode.System -> isSystemInDarkTheme()
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
    }

/** Material 3 in tidemeld's colours, with its standard type scale, as the Flutter app has it. */
@Composable
fun TidemeldTheme(dark: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
}
