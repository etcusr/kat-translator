package org.openoffline.translator.android

import android.os.Handler

/** Polls a running translation's partial text on the main thread and reports each change; stop() is final. */
internal class PartialPoller(private val main: Handler, private val read: () -> String?, private val changed: (String) -> Unit) {
    @Volatile private var stopped = false
    private var last = ""
    private val tick = object : Runnable { override fun run() {
        if (stopped) return
        val text = read()
        if (text != null && text != last) { last = text; changed(text) }
        main.postDelayed(this, INTERVAL_MS)
    } }
    init { main.postDelayed(tick, INTERVAL_MS) }
    fun stop() { stopped = true; main.removeCallbacks(tick) }
    private companion object { const val INTERVAL_MS = 120L }
}
