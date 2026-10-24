package com.holo.link

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import java.util.Calendar

/**
 * Today's minutes in the apps you picked (social media by default), sent to the face as
 * {"sm": {"m": minutes, "b": daily budget, "d": yyyymmdd}}. Checked every minute; sent when the
 * minute count changes (at most every 2 minutes), when the day rolls over, or on crossing the budget.
 * Needs "usage access" (Settings > Apps > Special app access > Usage access).
 */
class ScreenTimeFeed(private val ctx: Context) {

    private val handler = Handler(Looper.getMainLooper())
    private var lastSent: Triple<Int, Int, Int>? = null   // minutes, budget, day
    private var lastSentAt = 0L

    private val tick = object : Runnable {
        override fun run() {
            check()
            handler.postDelayed(this, 60_000L)
        }
    }

    fun start() {
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    fun stop() = handler.removeCallbacks(tick)

    private fun check() {
        if (!hasAccess(ctx)) {
            status = "no usage access"
            return
        }
        val m = minutesToday(ctx, Prefs.socialApps(ctx))
        val b = Prefs.budget(ctx)
        val day = today()
        minutes = m
        status = "$m of $b min today"
        val prev = lastSent
        val now = System.currentTimeMillis()
        val due = prev == null || prev.third != day || prev.second != b ||
            (prev.first < b) != (m < b) || (prev.first != m && now - lastSentAt >= 120_000L)
        if (due) {
            lastSent = Triple(m, b, day)
            lastSentAt = now
            Watch.send(mapOf("sm" to mapOf("m" to m, "b" to b, "d" to day)))
            Log.i(TAG, "social $m/$b")
        }
    }

    /** Forces a send on the next check, e.g. after the app list or budget changes. */
    fun poke() {
        lastSent = null
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    companion object {
        @Volatile var status = ""
        @Volatile var minutes = 0
        @Volatile var instance: ScreenTimeFeed? = null

        fun hasAccess(ctx: Context): Boolean {
            val ops = ctx.getSystemService(AppOpsManager::class.java)
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }

        fun today(): Int {
            val c = Calendar.getInstance()
            return c.get(Calendar.YEAR) * 10000 + (c.get(Calendar.MONTH) + 1) * 100 + c.get(Calendar.DAY_OF_MONTH)
        }

        /** Foreground minutes since local midnight across the given packages, from app open/close events. */
        fun minutesToday(ctx: Context, pkgs: Set<String>): Int {
            if (pkgs.isEmpty()) return 0
            val usm = ctx.getSystemService(UsageStatsManager::class.java)
            val c = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val now = System.currentTimeMillis()
            val events = usm.queryEvents(c.timeInMillis, now)
            val e = UsageEvents.Event()
            val open = HashMap<String, Long>()
            var total = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                val pkg = e.packageName ?: continue
                if (pkg !in pkgs) continue
                when (e.eventType) {
                    RESUMED -> if (pkg !in open) open[pkg] = e.timeStamp
                    PAUSED -> open.remove(pkg)?.let { total += e.timeStamp - it }
                }
            }
            for (t in open.values) total += now - t   // still in the app right now
            return (total / 60_000L).toInt()
        }

        // ACTIVITY_RESUMED / ACTIVITY_PAUSED (API 29 names for the old MOVE_TO_FOREGROUND/BACKGROUND).
        private const val RESUMED = 1
        private const val PAUSED = 2
    }
}
