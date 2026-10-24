package com.holo.link

import android.app.Application

class HoloLinkApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences("holo", MODE_PRIVATE)
        Watch.start(this, prefs.getBoolean("tethered", false))
    }
}
