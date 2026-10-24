package com.holo.link

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * The watch gets no weather from Garmin Connect on this phone, so this fetches it for the
 * phone's last known location from Open-Meteo (free, no key) every 15 minutes and sends
 * {"wx": {"c": WMO code, "t": now °C, "hi": high °C, "lo": low °C}} to the face.
 */
class WeatherFeed(private val ctx: Context) {

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            fetch()
            handler.postDelayed(this, 15 * 60 * 1000L)
        }
    }

    fun start() {
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    fun stop() = handler.removeCallbacks(tick)

    @SuppressLint("MissingPermission")
    private fun lastLocation(): Location? {
        val lm = ctx.getSystemService(LocationManager::class.java)
        return try {
            lm.getProviders(true).mapNotNull { lm.getLastKnownLocation(it) }.maxByOrNull { it.time }
        } catch (e: SecurityException) {
            status = "no location permission"
            null
        }
    }

    private fun fetch() {
        val loc = lastLocation() ?: run {
            if (status.isEmpty()) status = "no location yet"
            return
        }
        thread(name = "weather") {
            try {
                val url = URL(
                    "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f".format(loc.latitude, loc.longitude) +
                        "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min" +
                        "&timezone=auto&forecast_days=1"
                )
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 15000
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val j = JSONObject(body)
                val cur = j.getJSONObject("current")
                val daily = j.getJSONObject("daily")
                val wx = mapOf<String, Any>(
                    "c" to cur.getInt("weather_code"),
                    "t" to cur.getDouble("temperature_2m").toFloat(),
                    "hi" to daily.getJSONArray("temperature_2m_max").getDouble(0).toFloat(),
                    "lo" to daily.getJSONArray("temperature_2m_min").getDouble(0).toFloat()
                )
                status = "ok: ${wx["t"]}°C code ${wx["c"]}"
                Log.i(TAG, "weather $wx")
                handler.post { Watch.send(mapOf("wx" to wx)) }
            } catch (e: Exception) {
                status = "fetch failed: ${e.javaClass.simpleName}"
                Log.w(TAG, "weather fetch failed", e)
            }
        }
    }

    companion object {
        @Volatile var status = ""
    }
}
