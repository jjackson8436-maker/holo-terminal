package com.holo.link

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Status screen: permissions, Garmin link, what was last sent, and the social media ring settings. */
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
        val usage = Button(this).apply {
            text = "Usage access (for the social ring)"
            setOnClickListener { startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) }
        }
        val apps = Button(this).apply {
            text = "Choose social apps"
            setOnClickListener { chooseApps() }
        }
        val budget = Button(this).apply {
            text = "Daily social budget"
            setOnClickListener { chooseBudget() }
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
        for (v in listOf(info, access, usage, apps, budget, test, sim)) root.addView(v)
        setContentView(ScrollView(this).apply { addView(root) })
    }

    override fun onResume() {
        super.onResume()
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    private fun chooseApps() {
        val all = Prefs.launchable(this)
        val chosen = Prefs.socialApps(this).toMutableSet()
        val labels = all.map { it.second }.toTypedArray()
        val checked = all.map { it.first in chosen }.toBooleanArray()
        AlertDialog.Builder(this)
            .setTitle("Count these apps")
            .setMultiChoiceItems(labels, checked) { _, i, on ->
                if (on) chosen += all[i].first else chosen -= all[i].first
            }
            .setPositiveButton("Save") { _, _ ->
                Prefs.setSocialApps(this, chosen)
                ScreenTimeFeed.instance?.poke()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun chooseBudget() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            setText(Prefs.budget(this@MainActivity).toString())
        }
        AlertDialog.Builder(this)
            .setTitle("Minutes per day")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val m = input.text.toString().toIntOrNull()
                if (m != null && m > 0) {
                    Prefs.setBudget(this, m)
                    ScreenTimeFeed.instance?.poke()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun notificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
        return enabled.contains(packageName)
    }

    private fun show() {
        val np = MediaListener.current
        info.text = buildString {
            appendLine("Notification access: " + if (notificationAccess()) "on" else "OFF (tap below)")
            appendLine("Usage access: " + if (ScreenTimeFeed.hasAccess(this@MainActivity)) "on" else "OFF (tap below)")
            appendLine("Media listener: " + if (MediaListener.connected) "running" else "not running")
            appendLine("Garmin: ${Watch.status}")
            appendLine("Last send: ${Watch.lastResult.ifEmpty { "-" }}")
            appendLine("Weather: ${WeatherFeed.status.ifEmpty { "-" }}")
            appendLine("Social: ${ScreenTimeFeed.status.ifEmpty { "-" }}")
            appendLine("Counting ${Prefs.socialApps(this@MainActivity).size} apps")
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
