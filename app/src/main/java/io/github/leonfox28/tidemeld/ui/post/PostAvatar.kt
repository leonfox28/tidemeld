package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.media.WeiboImage

/** A round avatar, tappable when [onClick] is set. */
@Composable
fun PostAvatar(
    url: String?,
    label: String = "头像",
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    onClick: (() -> Unit)? = null,
) {
    val tappable =
        Modifier.testTag("avatar")
            .semantics { contentDescription = label }
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
    if (url == null) {
        Surface(
            modifier.size(size).clip(CircleShape).then(tappable),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Filled.Person,
                    contentDescription = null,
                    modifier = Modifier.size(size * 0.6f),
                )
            }
        }
    } else {
        WeiboImage(url, modifier.size(size).clip(CircleShape).then(tappable))
    }
}
