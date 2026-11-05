package io.github.leonfox28.tidemeld.ui.widget

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.data.model.WeiboUser

/** Weibo supplies its avatar and profile action to the shared presentation. */
@Composable
fun UserAvatar(
    user: WeiboUser?,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    onClick: ((WeiboUser) -> Unit)? = null,
) {
    io.github.leonfox28.tidemeld.ui.post.PostAvatar(
        user?.avatarUrl,
        user?.screenName ?: "头像",
        modifier,
        size,
        onClick = if (user != null && onClick != null) ({ onClick(user) }) else null,
    )
}

/** Weibo's verification mark: gold for people, blue for organisations. */
@Composable
fun VerifiedIcon(verifiedType: Int, modifier: Modifier = Modifier, size: Dp = 14.dp) {
    Icon(
        Icons.Filled.Verified,
        contentDescription = null,
        modifier = modifier.size(size),
        tint = if (verifiedType == 0) Color(0xFFFFA000) else Color(0xFF1E88E5),
    )
}

/** Whether [verifiedType] (`WeiboUser.verifiedType`) has a mark. */
fun showsVerified(verifiedType: Int?): Boolean = verifiedType != null && verifiedType in 0..7
