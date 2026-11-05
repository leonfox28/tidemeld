package io.github.leonfox28.tidemeld.core.errors

import kotlinx.coroutines.CancellationException

interface UserFacingFailure {
    val appFailure: AppFailure
}

sealed interface FailureRecovery {
    val label: String

    data object SignIn : FailureRecovery {
        override val label = "重新登录"
    }

    data class Verify(val url: String) : FailureRecovery {
        override val label = "去验证"
    }
}

data class AppFailure(
    override val message: String,
    val recovery: FailureRecovery? = null,
    val isNetwork: Boolean = false,
    val isCancelled: Boolean = false,
) : Exception(message), UserFacingFailure {
    override val appFailure: AppFailure
        get() = this

    companion object {
        fun of(error: Throwable?): AppFailure =
            when (error) {
                is UserFacingFailure -> error.appFailure
                is CancellationException -> AppFailure("已取消", isCancelled = true)
                else -> AppFailure("加载失败")
            }
    }
}
