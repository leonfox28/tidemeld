package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.util.formatCount

/** Only response lists the provider can load are offered as tabs. */
data class PostResponseTab(val id: String, val label: String, val count: Int)

@Composable
fun PostResponseHeader(
    tabs: List<PostResponseTab>,
    selected: String,
    likes: Int,
    onSelect: (String) -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().background(colors.surface)) {
        Row(Modifier.height(43.dp), verticalAlignment = Alignment.CenterVertically) {
            tabs.forEach { tab ->
                ResponseTabButton("${tab.label} ${formatCount(tab.count)}", tab.id == selected) {
                    onSelect(tab.id)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                "赞 ${formatCount(likes)}",
                Modifier.padding(end = 16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.onSurfaceVariant,
            )
        }
        HorizontalDivider()
    }
}

@Composable
private fun ResponseTabButton(label: String, selected: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxHeight().clickable(onClick = onClick).padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(Modifier.height(3.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = if (selected) colors.onSurface else colors.onSurfaceVariant,
            fontWeight = if (selected) FontWeight.SemiBold else null,
        )
        Spacer(Modifier.height(4.dp))
        Box(
            Modifier.size(20.dp, 3.dp)
                .background(
                    if (selected) colors.primary else Color.Transparent,
                    RoundedCornerShape(2.dp),
                )
        )
    }
}
