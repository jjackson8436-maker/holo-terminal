package com.holo.link

import android.content.Context
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp

const val TAG = "HoloLink"

/**
 * Talks to the Holo Terminal watch face through Garmin Connect's Connect IQ service.
 * Messages are Maps; the face receives them as a Dictionary in its background service.
 */
object Watch {
    // Holo Terminal's manifest id, without dashes.
    private const val APP_ID = "fa0565f599d143668c43ca4606f73b67"

    private var ciq: ConnectIQ? = null
    @Volatile private var ready = false
    // Latest unsent message of each kind (music, weather, social), sent once the SDK is ready.
    private val pending = java.util.concurrent.ConcurrentHashMap<String, Map<String, Any>>()

    @Volatile var status = "starting"
        private set
    @Volatile var lastResult = ""
        private set

    /** tethered = talk to the Connect IQ simulator over adb instead of the paired watch. */
    fun start(ctx: Context, tethered: Boolean) {
        val app = ctx.applicationContext
        val type = if (tethered) ConnectIQ.IQConnectType.TETHERED else ConnectIQ.IQConnectType.WIRELESS
        val c = ConnectIQ.getInstance(app, type)
        ciq = c
        status = "connecting (${type.name.lowercase()})"
        c.initialize(app, false, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                ready = true
                status = "ready (${type.name.lowercase()})"
                pending.values.toList().forEach { send(it) }
            }

            override fun onInitializeError(err: ConnectIQ.IQSdkErrorStatus) {
                ready = false
                status = "Garmin service error: $err"
                Log.w(TAG, status)
            }

            override fun onSdkShutDown() {
                ready = false
                status = "shut down"
            }
        })
    }

    fun send(msg: Map<String, Any>) {
        val kind = listOf("wx", "sm").firstOrNull { msg.containsKey(it) } ?: "np"
        pending[kind] = msg
        val c = ciq ?: return
        if (!ready) return
        val devices = try {
            c.connectedDevices ?: emptyList()
        } catch (e: Exception) {
            status = "Garmin service unavailable (${e.javaClass.simpleName})"
            Log.w(TAG, status, e)
            return
        }
        if (devices.isEmpty()) {
            lastResult = "no watch connected"
            Log.i(TAG, "send skipped: no watch connected")
            return
        }
        for (d in devices) {
            try {
                c.sendMessage(d, IQApp(APP_ID), msg) { _, _, s ->
                    lastResult = "${d.friendlyName}: $s"
                    Log.i(TAG, "sent $msg to ${d.friendlyName}: $s")
                }
            } catch (e: Exception) {
                lastResult = "${d.friendlyName}: ${e.javaClass.simpleName}"
                Log.w(TAG, "send failed", e)
            }
        }
        pending.remove(kind)
    }
}
