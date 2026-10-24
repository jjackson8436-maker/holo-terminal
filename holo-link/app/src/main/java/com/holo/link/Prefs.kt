package com.holo.link

import android.content.Context
import android.content.Intent

/** The social apps to count and the daily budget, kept in SharedPreferences. */
object Prefs {
    // Common social and video feeds; only the ones installed get preselected.
    val DEFAULT_SOCIAL = setOf(
        "com.instagram.android", "com.instagram.barcelona", "com.zhiliaoapp.musically", "com.ss.android.ugc.trill",
        "com.reddit.frontpage", "com.google.android.youtube", "com.facebook.katana", "com.twitter.android",
        "com.snapchat.android", "com.pinterest", "com.tumblr", "com.bereal.ft", "tv.twitch.android.app"
    )

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("holo", Context.MODE_PRIVATE)

    fun socialApps(ctx: Context): Set<String> {
        val p = prefs(ctx)
        if (!p.contains("social")) {
            val installed = launchable(ctx).map { it.first }.toSet()
            return DEFAULT_SOCIAL intersect installed
        }
        return p.getStringSet("social", emptySet()) ?: emptySet()
    }

    fun setSocialApps(ctx: Context, pkgs: Set<String>) = prefs(ctx).edit().putStringSet("social", pkgs).apply()

    fun budget(ctx: Context): Int = prefs(ctx).getInt("budget", 60)

    fun setBudget(ctx: Context, minutes: Int) = prefs(ctx).edit().putInt("budget", minutes).apply()

    /** (package, label) for every app with a launcher icon, sorted by label. */
    fun launchable(ctx: Context): List<Pair<String, String>> {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != ctx.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
    }
}
