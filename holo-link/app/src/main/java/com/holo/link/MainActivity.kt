package com.holo.link

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView

/** Status screen: notification access, Garmin link, what was last sent. */
class MainActivity : Activity() {

    private lateinit var info: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() {
            show()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad * 3, pad, pad)
        }
        info = TextView(this).apply { textSize = 16f }
        val access = Button(this).apply {
            text = "Notification access"
            setOnClickListener { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
        }
        val test = Button(this).apply {
            text = "Send test track"
            setOnClickListener { Watch.send(mapOf("t" to "Holo Link test", "a" to "Night City", "p" to true)) }
        }
        val prefs = getSharedPreferences("holo", MODE_PRIVATE)
        val sim = CheckBox(this).apply {
            text = "Simulator over adb (restarts the app)"
            isChecked = prefs.getBoolean("tethered", false)
            setOnCheckedChangeListener { _, on ->
                prefs.edit().putBoolean("tethered", on).commit()
                finishAffinity()
                Runtime.getRuntime().exit(0)
            }
        }
        root.addView(info)
        root.addView(access)
        root.addView(test)
        root.addView(sim)
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    private fun hasAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
        return enabled.contains(packageName)
    }

    private fun show() {
        val np = MediaListener.current
        info.text = buildString {
            appendLine("Notification access: " + if (hasAccess()) "on" else "OFF (tap below)")
            appendLine("Media listener: " + if (MediaListener.connected) "running" else "not running")
            appendLine("Garmin: ${Watch.status}")
            appendLine("Last send: ${Watch.lastResult.ifEmpty { "-" }}")
            appendLine("Weather: ${WeatherFeed.status.ifEmpty { "-" }}")
            appendLine()
            val title = np?.get("t") as? String
            if (title.isNullOrEmpty()) {
                appendLine("Now playing: nothing")
            } else {
                appendLine("Now playing: $title")
                appendLine("by ${np["a"]}" + if (np["p"] == true) "  (playing)" else "  (paused)")
            }
        }
    }
}
