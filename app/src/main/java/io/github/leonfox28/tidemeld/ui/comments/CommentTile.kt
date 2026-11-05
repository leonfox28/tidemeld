package io.github.leonfox28.tidemeld.ui.comments

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.Comment
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.ui.interactions.LikeKind
import io.github.leonfox28.tidemeld.ui.interactions.LikeState
import io.github.leonfox28.tidemeld.ui.interactions.LikeTarget
import io.github.leonfox28.tidemeld.ui.interactions.rememberLike
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.widget.UserAvatar
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.text.StatusText

/** Weibo fills the shared comment row without changing its links, likes or thread actions. */
@Composable
fun CommentTile(
    comment: Comment,
    modifier: Modifier = Modifier,
    authorId: String? = null,
    actions: StatusCardActions = StatusCardActions(),
    onThread: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    below: (@Composable () -> Unit)? = null,
) {
    val user = comment.user
    val shown =
        rememberLike(
            LikeTarget(LikeKind.Comment, comment.id),
            LikeState(comment.liked, comment.likesCount),
        )
    val meta =
        listOfNotNull(comment.createdAt?.let { formatPostTime(it) }, comment.source)
            .joinToString("  ")
    PostComment(
        author = user?.screenName ?: "微博用户",
        metadata = meta,
        modifier = modifier,
        isAuthor = user != null && user.id == authorId,
        onReply = onClick,
        onLongClick = onLongClick,
        avatar = { UserAvatar(user, size = 32.dp, onClick = actions.onUser) },
        content = {
            if (comment.text.isNotEmpty()) {
                StatusText(
                    comment.text,
                    Modifier.padding(top = 4.dp),
                    urls = comment.urls,
                    hiddenPictures = comment.pics.map { it.id },
                    style =
                        MaterialTheme.typography.bodyMedium.copy(
                            fontSize = 15.sp,
                            lineHeight = (15 * 1.45).sp,
                        ),
                    onLink = actions.onLink,
                )
            }
            if (comment.pics.isNotEmpty()) {
                PostCommentMedia(
                    comment.pics.map(MixedMedia::Pic),
                    actions.onPicture?.let { open ->
                        { index -> open(comment.pics, index, null) }
                    },
                )
            }
        },
        like = {
            PostCommentLike(shown.like.count, shown.like.liked, shown.onToggle, shown.pending)
        },
        replies =
            if (onThread != null && comment.replyCount > 0)
                ({
                    PostCommentThread(comment.replyCount, onThread) {
                        val style =
                            MaterialTheme.typography.bodyMedium.let {
                                it.copy(lineHeight = it.fontSize * 1.4f)
                            }
                        for (reply in comment.replies) {
                            StatusText(
                                reply.text,
                                Modifier.padding(bottom = 4.dp),
                                urls = reply.urls,
                                author = reply.user?.screenName,
                                style = style,
                                onLink = actions.onLink,
                            )
                        }
                    }
                })
            else null,
        below = below,
    )
}
