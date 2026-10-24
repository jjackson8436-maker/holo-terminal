package com.holo.link

import android.content.ComponentName
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService

/**
 * Watches the phone's media sessions (Spotify or any player) and sends the current track
 * to the watch whenever the title, artist or play/pause state changes.
 */
class MediaListener : NotificationListenerService() {

    private var msm: MediaSessionManager? = null
    private val tracked = mutableListOf<Pair<MediaController, MediaController.Callback>>()
    private val handler = Handler(Looper.getMainLooper())
    private var last: Map<String, Any>? = null
    private var weather: WeatherFeed? = null

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        track(list ?: emptyList())
    }

    override fun onListenerConnected() {
        val m = getSystemService(MediaSessionManager::class.java)
        msm = m
        val me = ComponentName(this, MediaListener::class.java)
        m.addOnActiveSessionsChangedListener(sessionsChanged, me, handler)
        track(m.getActiveSessions(me))
        connected = true
        weather = WeatherFeed(this).also { it.start() }
    }

    override fun onListenerDisconnected() {
        msm?.removeOnActiveSessionsChangedListener(sessionsChanged)
        untrack()
        weather?.stop()
        connected = false
    }

    private fun track(list: List<MediaController>) {
        untrack()
        for (c in list) {
            val cb = object : MediaController.Callback() {
                override fun onMetadataChanged(metadata: MediaMetadata?) = schedule()
                override fun onPlaybackStateChanged(state: PlaybackState?) = schedule()
                override fun onSessionDestroyed() = schedule()
            }
            c.registerCallback(cb, handler)
            tracked += c to cb
        }
        schedule()
    }

    private fun untrack() {
        for ((c, cb) in tracked) c.unregisterCallback(cb)
        tracked.clear()
    }

    // Players fire several callbacks per track change; settle before sending.
    private fun schedule() {
        handler.removeCallbacks(push)
        handler.postDelayed(push, 400)
    }

    private val push = Runnable {
        val controllers = tracked.map { it.first }
        val pick = controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: controllers.firstOrNull { it.packageName == SPOTIFY }
            ?: controllers.firstOrNull()
        val md = pick?.metadata
        val title = md?.getString(MediaMetadata.METADATA_KEY_TITLE)
        val msg: Map<String, Any> = if (pick == null || md == null || title.isNullOrBlank()) {
            mapOf("t" to "", "a" to "", "p" to false)
        } else {
            mapOf(
                "t" to title,
                "a" to (md.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""),
                "p" to (pick.playbackState?.state == PlaybackState.STATE_PLAYING)
            )
        }
        if (msg != last) {
            last = msg
            current = msg
            Watch.send(msg)
        }
    }

    companion object {
        private const val SPOTIFY = "com.spotify.music"
        @Volatile var connected = false
        @Volatile var current: Map<String, Any>? = null
    }
}
