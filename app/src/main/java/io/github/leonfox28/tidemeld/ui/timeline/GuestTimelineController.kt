package io.github.leonfox28.tidemeld.ui.timeline

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.core.session.SessionController
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.data.api.GuestWeiboApi
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.Status
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class GuestTimelineController(
    private val api: GuestWeiboApi?,
    session: SessionController,
    scope: CoroutineScope,
) : PagedController<Status>(scope) {
    init {
        scope.launch {
            session.state
                .map { (it as? SessionState.SignedIn)?.account?.uid }
                .distinctUntilChanged()
                .drop(1)
                .collect { reset() }
        }
    }

    override suspend fun fetchPage(cursor: String?): Paged<Status> =
        api?.fetchTimeline() ?: throw WeiboApiException("游客内容暂不可用，请稍后重试")

    override fun idOf(item: Status) = item.id
}
