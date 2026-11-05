package io.github.leonfox28.tidemeld.ui.widget.status

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.R
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.data.model.PageCard
import io.github.leonfox28.tidemeld.data.model.PicInfo
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.StatusVisibility
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.ui.interactions.LikeKind
import io.github.leonfox28.tidemeld.ui.interactions.LikeTarget
import io.github.leonfox28.tidemeld.ui.interactions.like
import io.github.leonfox28.tidemeld.ui.interactions.rememberLike
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.widget.PicGrid
import io.github.leonfox28.tidemeld.ui.widget.UserAvatar
import io.github.leonfox28.tidemeld.ui.widget.VerifiedIcon
import io.github.leonfox28.tidemeld.ui.widget.WideCardFrom
import io.github.leonfox28.tidemeld.ui.widget.showsVerified
import io.github.leonfox28.tidemeld.ui.widget.text.StatusLink
import io.github.leonfox28.tidemeld.ui.widget.text.StatusText

/**
 * What tapping parts of a status (or comment) leads to. A null callback leaves its target inert.
 */
data class StatusCardActions(
    val onLike: ((Status) -> Unit)? = null,
    /** The card itself, or the retweeted post inside it. */
    val onOpen: ((Status) -> Unit)? = null,
    val onLink: ((StatusLink) -> Unit)? = null,
    val onUser: ((WeiboUser) -> Unit)? = null,
    /** "展开" on a truncated long post. */
    val onExpand: ((Status) -> Unit)? = null,
    /**
     * A picture, among [pics]; the status they belong to (none for a comment's) is where the viewer
     * gets a live photo's video afresh once its URL has expired.
     */
    val onPicture: ((pics: List<PicInfo>, index: Int, status: Status?) -> Unit)? = null,
    /**
     * A video; the index picks one in a post mixing pictures and videos, as `Status.videoAt` does.
     */
    val onVideo: ((status: Status, index: Int?) -> Unit)? = null,
    /** The repost count, which reposts the card's post. */
    val onRepost: ((Status) -> Unit)? = null,
    /** Deleting a post of the signed-in user's, offered on their posts only. */
    val onDelete: ((Status) -> Unit)? = null,
)

/**
 * A status as shown in a timeline, or atop its detail page when [detail], where the card itself
 * isn't tappable and the counts move to the page's tabs.
 *
 * Given [WideCardFrom] or more across, as a [FeedWidth] timeline gives it, a timeline card puts its
 * pictures, video or retweeted post beside its text rather than under it: the text keeps to about
 * the length of line it has on a phone, the media takes the rest, and the card takes less height.
 * The counts stay under the text, at the foot of the card when the media runs further down.
 * Text-only cards keep their text to the left, so all the text of a timeline lines up, in lines no
 * longer than a reading column's.
 */
@Composable
fun StatusCard(
    status: Status,
    modifier: Modifier = Modifier,
    actions: StatusCardActions = StatusCardActions(),
    detail: Boolean = false,
) {
    PostCard(
        modifier = modifier,
        detail = detail,
        activity = status.activity,
        onOpen = actions.onOpen?.let { { it(status) } },
        header = { Header(status, actions) },
        body = { Body(status, actions, withMedia = detail || status.retweeted != null) },
        aside =
            when {
                status.retweeted != null -> ({ Retweeted(status.retweeted, actions) })
                !detail && hasMedia(status) -> ({ Media(status, actions) })
                else -> null
            },
        footer = { Counts(status, actions) },
    )
}

@Composable
private fun Retweeted(status: Status, actions: StatusCardActions) {
    val onOpen = actions.onOpen
    // Deleted or hidden posts come without an author or time and can't be
    // opened; those in `statuses/mentions` may lack only the author.
    val canOpen = onOpen != null && (status.user != null || status.createdAt != null)
    QuotedPost(onOpen = if (canOpen) ({ onOpen!!(status) }) else null) {
        Body(status, actions, nested = true)
    }
}

@Composable
private fun Header(status: Status, actions: StatusCardActions) {
    val user = status.user
    val meta =
        listOfNotNull(
                status.createdAt?.let { formatPostTime(it) },
                status.source?.let { "来自 $it" },
                status.region,
            )
            .joinToString("  ")
    val verified = user?.verifiedType
    val onUser = actions.onUser
    val onDelete = actions.onDelete
    val tags =
        listOfNotNull(
            "置顶".takeIf { status.pinned },
            status.visibility.label.takeIf { status.visibility != StatusVisibility.Public },
            "广告".takeIf { status.isAd },
        )
    PostHeader(
        name = user?.screenName ?: "微博用户",
        metadata = meta,
        sourceIcon = R.drawable.ic_platform_weibo,
        sourceLabel = "微博",
        tags = tags,
        onAuthor = if (user != null && onUser != null) ({ onUser(user) }) else null,
        avatar = { UserAvatar(user, onClick = onUser) },
        badge = {
            if (showsVerified(verified)) {
                Spacer(Modifier.width(4.dp))
                VerifiedIcon(verified!!)
            }
        },
        menu = {
            if (onDelete != null && user != null) OwnStatusMenu(user.id) { onDelete(status) }
        },
    )
}

/** A menu for the signed-in user's own posts; nothing on others'. */
@Composable
private fun OwnStatusMenu(authorId: String, onDelete: () -> Unit) {
    val session by LocalAppGraph.current.session.state.collectAsStateWithLifecycle()
    if ((session as? SessionState.SignedIn)?.account?.uid != authorId) return
    IconButton(onClick = onDelete, modifier = Modifier.size(40.dp)) {
        Icon(Icons.Filled.MoreHoriz, contentDescription = "更多")
    }
}

/** The pictures, video or linked page of a status, if it has any. */
private fun hasMedia(status: Status): Boolean {
    val isRetweet = status.retweeted != null
    return status.pics.isNotEmpty() ||
        status.mixedMedia.isNotEmpty() ||
        (!isRetweet && (status.video != null || status.pageCard != null))
}

@Composable
private fun Media(status: Status, actions: StatusCardActions) {
    // A retweet carries a copy of its source's page_info; show it only once,
    // inside the retweeted post.
    val isRetweet = status.retweeted != null
    val video = if (isRetweet) null else status.video
    val card = if (isRetweet) null else status.pageCard
    val onPicture = actions.onPicture
    val onVideo = actions.onVideo
    when {
        status.pics.isNotEmpty() ->
            PicGrid(
                status.pics.map { MixedMedia.Pic(it) },
                total = status.picCount,
                onClick = onPicture?.let { { i: Int -> it(status.pics, i, status) } },
            )
        status.mixedMedia.isNotEmpty() -> MixedGrid(status, actions)
        video != null -> VideoCover(video, onVideo?.let { { it(status, null) } })
        card != null -> PageCardView(card)
    }
}

// Pictures open in the viewer among the post's other pictures; videos play
// by their place among its videos.
@Composable
private fun MixedGrid(status: Status, actions: StatusCardActions) {
    val items = status.mixedMedia
    PicGrid(items, total = status.picCount) { i ->
        val before = items.take(i)
        when (items[i]) {
            is MixedMedia.Pic ->
                actions.onPicture?.invoke(
                    status.mixedPics,
                    before.count { it is MixedMedia.Pic },
                    status,
                )
            is MixedMedia.Video ->
                actions.onVideo?.invoke(status, before.count { it is MixedMedia.Video })
        }
    }
}

/**
 * Text and media of a status, or of the post it retweets when [nested]; without [withMedia], only
 * the text, the media being shown elsewhere.
 */
@Composable
private fun Body(
    status: Status,
    actions: StatusCardActions,
    nested: Boolean = false,
    withMedia: Boolean = true,
) {
    Column {
        if (status.text.isNotEmpty() || (nested && status.user != null)) {
            StatusText(
                status.text,
                urls = status.urls,
                author = if (nested) status.user?.screenName else null,
                style =
                    MaterialTheme.typography.bodyMedium.copy(
                        fontSize = 15.sp,
                        lineHeight = (15 * 1.45).sp,
                    ),
                onLink = actions.onLink,
                onExpand = actions.onExpand?.let { { it(status) } },
            )
        }
        if (withMedia && hasMedia(status)) {
            Spacer(Modifier.height(8.dp))
            Media(status, actions)
        }
    }
}

@Composable
private fun PageCardView(card: PageCard) {
    val colors = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(colors.surfaceContainer),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        card.imageUrl?.let { WeiboImage(it, Modifier.size(64.dp)) }
        Column(Modifier.weight(1f).padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(
                card.title,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.titleSmall,
            )
            card.description?.let {
                Text(
                    it,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Repost, comment and like counts; the repost count is a repost button and the like count a like
 * button.
 */
@Composable
private fun Counts(status: Status, actions: StatusCardActions) {
    val shown = rememberLike(LikeTarget(LikeKind.Status, status.id), status.like)
    PostInteractionBar(
        PostInteractionActions(
            reposts = status.repostsCount,
            comments = status.commentsCount,
            likes = shown.like.count,
            liked = shown.like.liked,
            likePending = shown.pending,
            onRepost = actions.onRepost?.let { { it(status) } },
            onComment = actions.onOpen?.let { { it(status) } },
            onLike = actions.onLike?.let { { it(status) } } ?: shown.onToggle,
        )
    )
}
