package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.errors.*

@Composable
fun FailureNotice(failure: AppFailure, onRecover: ((FailureRecovery) -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            failure.message,
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
        if (failure.recovery != null && onRecover != null)
            TextButton(onClick = { onRecover(failure.recovery) }) { Text(failure.recovery.label) }
    }
}
