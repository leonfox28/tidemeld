package io.github.leonfox28.tidemeld

import android.app.Application

class TidemeldApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph.create(this)
    }
}
