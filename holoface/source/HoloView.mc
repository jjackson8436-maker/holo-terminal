import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Seven themes for the Venu Sq 2's 320x360 AMOLED screen, each a drawing style plus a palette.
// Claude usage is two rings around the screen edge, filling clockwise from the top:
// outer = 5-hour session, middle = week. With the Holo Link phone app, an innermost ring shows
// today's social media time against a daily budget. The "labels" setting names the rings.
class HoloView extends WatchUi.WatchFace {

    private var _awake as Boolean = true;
    private var _w as Number = 320;
    private var _h as Number = 360;
    private var _fontStyle as Number = -1;
    private var _fTime as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _fSmall as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fDate as Graphics.FontType = Graphics.FONT_SMALL;
    private var _fLabel as Graphics.FontType = Graphics.FONT_XTINY;
    // How far the date moves down to make room for labels inside a third ring.
    private var _dateDrop as Number = 0;

    // Drawing styles.
    private const TERMINAL = 0;   // VT323, scanlines, dashed rings, phosphor glow
    private const NEON = 1;       // Orbitron, glitched time, hazard stripes
    private const OUTRUN = 2;     // Orbitron, striped sunset over a perspective grid
    private const RAIN = 3;       // VT323 over falling code
    private const MONO = 4;       // Orbitron, plain

    // Per theme: style, then palette [background, main/outer ring, dim, inner ring, warn, faint track, accent, social ring].
    // Order matches the theme list in settings.xml.
    private const STYLE = [0, 0, 1, 1, 2, 3, 4];
    private const PAL = [
        [0x000000, 0x1BFF80, 0x0B6B36, 0x0FB85A, 0xFFB000, 0x06301A, 0x9CFFC8, 0xD8FFE8],   // Wasteland
        [0x000000, 0xFFB000, 0x6B4A00, 0xD08A00, 0xFF4A20, 0x2A1C00, 0xFFD27A, 0xFFF0C8],   // Amber
        [0x000000, 0xFCEE0A, 0x4A4600, 0x00F0FF, 0xFF2A6D, 0x14142E, 0xFF2A6D, 0xB86BFF],   // Neon
        [0x000000, 0x00E5FF, 0x0A4A55, 0xFF8A00, 0xFF3030, 0x0A1A22, 0xFF8A00, 0xFFFFFF],   // Grid
        [0x0A0014, 0xFF6AD5, 0x5A2050, 0x26D7FF, 0xFFE14D, 0x24103A, 0xFFB000, 0xFFB000],   // Outrun
        [0x000000, 0x00FF41, 0x005F1A, 0x00B030, 0xE0FFE0, 0x002208, 0x8CFF9E, 0xD0FFD0],   // Rain
        [0x000000, 0xFFFFFF, 0x4A4A4A, 0x9A9A9A, 0xFF5050, 0x1A1A1A, 0xCFCFCF, 0x6E6E6E]    // Mono
    ];

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    private function theme() as Number {
        var t = Application.Properties.getValue("theme");
        return (t instanceof Number && t >= 0 && t < PAL.size()) ? t : 2;
    }

    private function labelsOn() as Boolean {
        return Application.Properties.getValue("labels") == true;
    }

    private function loadFonts(style as Number) as Void {
        var vt = (style == TERMINAL || style == RAIN);
        var key = vt ? 0 : 1;
        if (key == _fontStyle) { return; }
        if (vt) {
            _fTime = WatchUi.loadResource(Rez.Fonts.VtTime) as Graphics.FontType;
            _fSmall = WatchUi.loadResource(Rez.Fonts.VtSmall) as Graphics.FontType;
            _fDate = _fSmall;
            _fLabel = WatchUi.loadResource(Rez.Fonts.VtLabel) as Graphics.FontType;
        } else {
            _fTime = WatchUi.loadResource(Rez.Fonts.OrbTime) as Graphics.FontType;
            _fSmall = WatchUi.loadResource(Rez.Fonts.OrbSmall) as Graphics.FontType;
            _fDate = WatchUi.loadResource(Rez.Fonts.OrbDate) as Graphics.FontType;
            _fLabel = WatchUi.loadResource(Rez.Fonts.OrbLabel) as Graphics.FontType;
        }
        _fontStyle = key;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var th = theme();
        var style = STYLE[th] as Number;
        loadFonts(style);
        var p = PAL[th] as Array<Number>;
        dc.setColor(p[0], p[0]);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var timeStr = hour.format("%02d") + ":" + clock.min.format("%02d");

        if (!_awake) {
            // Always-on: dim time only, nudged each minute against burn-in.
            var dx = (clock.min % 5) * 3 - 6;
            dc.setColor(p[2], Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2 + dx, _h / 2, _fTime, timeStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var u = usage();
        var sm = social();
        _dateDrop = (sm != null && labelsOn()) ? 14 : 0;
        if (style == TERMINAL || style == RAIN) {
            drawTerminal(dc, p, timeStr, u, style == RAIN, clock.hour * 60 + clock.min);
        } else if (style == NEON) {
            drawNeon(dc, p, timeStr, u, clock.min);
        } else if (style == OUTRUN) {
            drawOutrun(dc, p, timeStr, u);
        } else {
            drawMono(dc, p, timeStr, u);
        }
        if (sm != null) {
            socialRing(dc, p, style, sm);
        }
        if (labelsOn()) {
            ringLabels(dc, p, u, sm);
        }
    }

    // ---------- data ----------

    private function dateStr() as String {
        var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return (d.day_of_week as String).toUpper() + " " + d.day.format("%02d") + " " + (d.month as String).toUpper();
    }

    private function steps() as String {
        var info = ActivityMonitor.getInfo();
        return (info.steps != null) ? (info.steps as Number).toString() : "--";
    }

    private function heartRate() as String {
        var a = Activity.getActivityInfo();
        if (a != null && a.currentHeartRate != null) {
            return (a.currentHeartRate as Number).toString();
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var s = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return (s.heartRate as Number).toString();
            }
        }
        return "--";
    }

    private function battery() as Number {
        return System.getSystemStats().battery.toNumber();
    }

    // [sessionPct or -1, weeklyPct or -1, stale]
    private function usage() as Array {
        var u = Application.Storage.getValue("usage");
        if (!(u instanceof Dictionary)) {
            return [-1, -1, true];
        }
        var now = Time.now().value();
        var s = toPct(u["s"]);
        var w = toPct(u["w"]);
        var sr = u["sr"];
        var wr = u["wr"];
        var t = u["t"];
        // A window that has already reset reads 0 until the next fetch says otherwise.
        if (sr instanceof Number && sr <= now) { s = 0; }
        if (wr instanceof Number && wr <= now) { w = 0; }
        var stale = !(t instanceof Number) || (now - (t as Number)) > 6 * 3600;
        return [s, w, stale];
    }

    private function toPct(v) as Number {
        if (v instanceof Number) { return v; }
        if (v instanceof Float || v instanceof Double) { return v.toNumber(); }
        return -1;
    }

    // ---------- Terminal (Wasteland, Amber) and Rain ----------

    private function drawTerminal(dc as Graphics.Dc, p as Array<Number>, timeStr as String, u as Array, rain as Boolean, seed as Number) as Void {
        if (rain) {
            codeRain(dc, p, seed);
            // Keep the text rows clear of rain.
            dc.setColor(p[0], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(30, 40, _w - 60, 34);
            dc.fillRectangle(30, 76, _w - 60, 30);
            dc.fillRectangle(30, _h / 2 + 30, _w - 60, 30);
            dc.fillRectangle(30, _h - 100, _w - 60, 52);
        } else {
            dc.setColor(p[5], Graphics.COLOR_TRANSPARENT);
            for (var y = 0; y < _h; y += 3) {
                dc.drawLine(0, y, _w, y);
            }
        }

        ring(dc, 6, 7, 26, u[0] as Number, u[2] as Boolean, p[1], p[4], p[5], p[2], 9, 4);
        ring(dc, 18, 4, 20, u[1] as Number, u[2] as Boolean, p[3], p[4], p[5], p[2], 6, 4);

        var cx = _w / 2;
        dc.setColor(p[6], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 38 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        header(dc, 90, p[1], p[3], p[2], p[2]);

        // Time with a soft phosphor glow.
        var ty = _h / 2 - 12;
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (rain) {
            // Clear a box behind the digits so the rain doesn't run through them.
            dc.setColor(p[0], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx - 132, ty - 40, 264, 80);
        }
        dc.setColor(p[2], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 2, ty, _fTime, timeStr, j);
        dc.drawText(cx + 2, ty, _fTime, timeStr, j);
        dc.drawText(cx, ty - 2, _fTime, timeStr, j);
        dc.drawText(cx, ty + 2, _fTime, timeStr, j);
        dc.setColor(rain ? p[6] : p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, _fTime, timeStr, j);

        nowPlaying(dc, ty + 46, false, p[3], p[3], p[1]);
        stats(dc, _h - 96, p[1], p[4], p[5]);
    }

    // Columns of dim falling characters, reshuffled each minute.
    private function codeRain(dc as Graphics.Dc, p as Array<Number>, seed as Number) as Void {
        var chars = "0123456789ABCDEFXZ:=+<>*";
        var n = chars.length();
        var r = seed * 7919 + 17;
        var fh = 22;
        for (var x = 26; x < _w - 20; x += 17) {
            r = (r * 1103515245 + 12345) & 0x7FFFFFFF;
            var start = (r % 14) - 4;
            r = (r * 1103515245 + 12345) & 0x7FFFFFFF;
            var len = 3 + r % 7;
            for (var k = 0; k < len; k++) {
                var row = start + k;
                if (row < 0) { continue; }
                var y = 26 + row * fh;
                if (y > _h - 40) { break; }
                r = (r * 1103515245 + 12345) & 0x7FFFFFFF;
                var c = r % n;
                dc.setColor(k == len - 1 ? p[2] : p[5], Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, _fLabel, chars.substring(c, c + 1) as String, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    // ---------- Neon (Neon, Grid) ----------

    private function drawNeon(dc as Graphics.Dc, p as Array<Number>, timeStr as String, u as Array, minute as Number) as Void {
        ring(dc, 6, 6, 30, u[0] as Number, u[2] as Boolean, p[1], p[4], p[5], p[2], 0, 0);
        ring(dc, 17, 3, 22, u[1] as Number, u[2] as Boolean, p[3], p[4], p[5], p[2], 0, 0);

        var cx = _w / 2;
        // Date: big, with a ghost in the accent color.
        dc.setColor(p[6], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 2, 38 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 36 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        header(dc, 90, p[1], p[3], p[2], p[3]);

        // Glitched time: accent and inner-ring-color ghosts behind the main color, plus a cut slice.
        var ty = _h / 2 - 24;
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(p[6], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 4, ty + 2, _fTime, timeStr, j);
        dc.setColor(p[3], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 4, ty - 2, _fTime, timeStr, j);
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, _fTime, timeStr, j);
        // The slice skims the top or bottom quarter of the digits so they stay readable.
        var gy = (minute % 2 == 0) ? ty - 21 + (minute % 3) * 2 : ty + 15 + (minute % 3) * 2;
        dc.setColor(p[0], Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 130, gy, 260, 2);
        dc.setColor(p[3], Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx + 70 - (minute % 5) * 30, gy - 2, 30, 2);

        // Hazard stripes under the time.
        var hy = ty + 40;
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 6; i++) {
            var x0 = cx - 40 + i * 14;
            dc.fillPolygon([[x0, hy + 8], [x0 + 6, hy], [x0 + 12, hy], [x0 + 6, hy + 8]]);
        }

        nowPlaying(dc, ty + 52, true, p[1], p[3], p[6]);
        stats(dc, _h - 84, p[3], p[4], p[5]);
    }

    // ---------- Outrun ----------

    private function drawOutrun(dc as Graphics.Dc, p as Array<Number>, timeStr as String, u as Array) as Void {
        var cx = _w / 2;
        var ty = _h / 2 - 24;
        var horizon = ty + 56;

        // Big striped sun behind the time, peeking out above and below the digits:
        // yellow at the top fading to pink, gaps in the lower part.
        var r = 95;
        var sy = horizon;
        for (var y = sy - r; y < horizon; y++) {
            var below = y - (sy - r / 2);
            if (below > 0 && below % 8 < 2 + below / 10) { continue; }
            var dy = y - sy;
            var half = Math.sqrt((r * r - dy * dy).toFloat()).toNumber();
            dc.setColor(lerp(0xFFE14D, 0xFF2A8A, (y - (sy - r)).toFloat() / r), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - half, y, cx + half, y);
        }

        // Perspective grid floor.
        dc.setColor(p[2], Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, horizon, _w, horizon);
        var gap = 4;
        var gy = horizon;
        while (gy < _h) {
            gy += gap;
            gap += 3;
            dc.drawLine(0, gy, _w, gy);
        }
        for (var i = -8; i <= 8; i++) {
            dc.drawLine(cx + i * 10, horizon, cx + i * 70, _h);
        }

        ring(dc, 6, 6, 30, u[0] as Number, u[2] as Boolean, p[1], p[4], p[5], p[2], 0, 0);
        ring(dc, 17, 3, 22, u[1] as Number, u[2] as Boolean, p[3], p[4], p[5], p[2], 0, 0);

        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 2, 38 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(p[3], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 36 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        header(dc, 90, p[3], p[1], p[2], p[1]);

        // Time in white with a dark outline and a pink drop, so it reads over the sun.
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 4, ty + 4, _fTime, timeStr, j);
        dc.setColor(p[0], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 2, ty, _fTime, timeStr, j);
        dc.drawText(cx + 2, ty, _fTime, timeStr, j);
        dc.drawText(cx, ty - 2, _fTime, timeStr, j);
        dc.drawText(cx, ty + 2, _fTime, timeStr, j);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, _fTime, timeStr, j);

        nowPlaying(dc, ty + 60, true, p[3], p[1], p[6]);
        stats(dc, _h - 84, p[3], p[4], p[5]);
    }

    // Mixes two 0xRRGGBB colors; t from 0 (a) to 1 (b).
    private function lerp(a as Number, b as Number, t as Float) as Number {
        var ar = (a >> 16) & 0xFF;
        var ag = (a >> 8) & 0xFF;
        var ab = a & 0xFF;
        var r = ar + ((((b >> 16) & 0xFF) - ar) * t).toNumber();
        var g = ag + ((((b >> 8) & 0xFF) - ag) * t).toNumber();
        var bl = ab + (((b & 0xFF) - ab) * t).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // ---------- Mono ----------

    private function drawMono(dc as Graphics.Dc, p as Array<Number>, timeStr as String, u as Array) as Void {
        ring(dc, 6, 4, 30, u[0] as Number, u[2] as Boolean, p[1], p[4], p[5], p[2], 0, 0);
        ring(dc, 15, 2, 22, u[1] as Number, u[2] as Boolean, p[3], p[4], p[5], p[2], 0, 0);

        var cx = _w / 2;
        dc.setColor(p[3], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 36 + _dateDrop, _fDate, dateStr(), Graphics.TEXT_JUSTIFY_CENTER);
        header(dc, 90, p[1], p[3], p[2], p[3]);

        var ty = _h / 2 - 24;
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, _fTime, timeStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(p[2], Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 60, ty + 42, cx + 60, ty + 42);

        nowPlaying(dc, ty + 52, true, p[1], p[3], p[3]);
        stats(dc, _h - 84, p[6], p[4], p[5]);
    }

    // ---------- social media ring ----------

    // [pct of budget (capped at 100), over budget, minutes, budget, stale] from Holo Link, or null
    // if the phone app has never sent any. A reading from an earlier day counts as 0 minutes.
    private function social() as Array? {
        var sm = Application.Storage.getValue("sm");
        if (!(sm instanceof Dictionary)) { sm = demoSocial(); }
        if (!(sm instanceof Dictionary)) { return null; }
        var m = sm["m"];
        var b = sm["b"];
        if (!(m instanceof Number) || !(b instanceof Number) || b <= 0) { return null; }
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var today = (d.year as Number) * 10000 + (d.month as Number) * 100 + (d.day as Number);
        if (sm["d"] != today) { m = 0; }
        var got = sm["got"];
        var stale = !(got instanceof Number) || Time.now().value() - got > 30 * 60;
        var pct = m * 100 / b;
        return [pct > 100 ? 100 : pct, m >= b, m, b, stale];
    }

    // Sample reading so the ring can be judged in the simulator. Stripped from release builds.
    (:debug)
    private function demoSocial() as Dictionary? {
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return {"m" => 42, "b" => 60, "d" => (d.year as Number) * 10000 + (d.month as Number) * 100 + (d.day as Number),
                "got" => Time.now().value()};
    }

    (:release)
    private function demoSocial() as Dictionary? {
        return null;
    }

    // Innermost ring, in the theme's social color; the warn color once over budget.
    private function socialRing(dc as Graphics.Dc, p as Array<Number>, style as Number, sm as Array) as Void {
        var c = (sm[1] as Boolean) ? p[4] : p[7];
        var stale = sm[4] as Boolean;
        if (style == TERMINAL || style == RAIN) {
            ring(dc, 28, 3, 16, sm[0] as Number, stale, c, c, p[5], p[2], 4, 4);
        } else if (style == MONO) {
            ring(dc, 23, 2, 16, sm[0] as Number, stale, c, c, p[5], p[2], 0, 0);
        } else {
            ring(dc, 26, 3, 16, sm[0] as Number, stale, c, c, p[5], p[2], 0, 0);
        }
    }

    // ---------- ring labels ----------

    // Names the rings for people new to the face: outer = session, inner = week.
    private function ringLabels(dc as Graphics.Dc, p as Array<Number>, u as Array, sm as Array?) as Void {
        var y = (sm == null) ? 21 : 31;
        if (sm != null) {
            dc.setColor((sm[1] as Boolean) ? p[4] : p[7], Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, _h - 50, _fLabel, "SOCIAL " + (sm[2] as Number) + "/" + (sm[3] as Number) + " MIN",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(p[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(34, y, _fLabel, "SESSION " + pct(u[0] as Number), Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(p[3], Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w - 34, y, _fLabel, "WEEK " + pct(u[1] as Number), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function pct(v as Number) as String {
        return v < 0 ? "--" : v.toString() + "%";
    }

    // ---------- weather + phone link ----------

    // [kind, temperature text, high/low text] or null. kind: 0 sun, 1 part cloud, 2 cloud, 3 rain, 4 storm, 5 snow, 6 fog
    private function weather() as Array? {
        var f = System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
        var c = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
        if (c == null || c.temperature == null) {
            return phoneWeather(f);
        }
        var t = temp(c.temperature, f);
        var hl = "";
        if (c.highTemperature != null && c.lowTemperature != null) {
            hl = temp(c.highTemperature, f) + "/" + temp(c.lowTemperature, f);
        }
        return [weatherKind(c.condition), t + "°", hl];
    }

    // Weather sent by Holo Link (Open-Meteo for the phone's location), used when Garmin's
    // own weather is missing. Ignored once it's over 3 hours old.
    private function phoneWeather(f as Boolean) as Array? {
        var wx = Application.Storage.getValue("wx");
        if (!(wx instanceof Dictionary) || wx["t"] == null) { return null; }
        var got = wx["got"];
        if (got instanceof Number && Time.now().value() - got > 3 * 3600) { return null; }
        var hl = (wx["hi"] != null && wx["lo"] != null) ? temp(wx["hi"], f) + "/" + temp(wx["lo"], f) : "";
        return [wmoKind(wx["c"]), temp(wx["t"], f) + "°", hl];
    }

    // WMO weather code (Open-Meteo) to the same icon kinds as weatherKind().
    private function wmoKind(code) as Number {
        if (!(code instanceof Number)) { return 6; }
        if (code <= 1) { return 0; }
        if (code == 2) { return 1; }
        if (code == 3) { return 2; }
        if (code == 45 || code == 48) { return 6; }
        if (code >= 95) { return 4; }
        if ((code >= 71 && code <= 77) || code == 85 || code == 86) { return 5; }
        return 3;   // drizzle, rain, freezing rain, showers
    }

    private function temp(celsius, fahrenheit as Boolean) as String {
        var v = celsius.toFloat();
        if (fahrenheit) { v = v * 9.0 / 5.0 + 32.0; }
        return Math.round(v).toNumber().toString();
    }

    private function weatherKind(cond) as Number {
        var groups = [
            [Weather.CONDITION_CLEAR, Weather.CONDITION_MOSTLY_CLEAR, Weather.CONDITION_FAIR],
            [Weather.CONDITION_PARTLY_CLOUDY, Weather.CONDITION_PARTLY_CLEAR, Weather.CONDITION_THIN_CLOUDS],
            [Weather.CONDITION_CLOUDY, Weather.CONDITION_MOSTLY_CLOUDY, Weather.CONDITION_WINDY],
            [Weather.CONDITION_RAIN, Weather.CONDITION_LIGHT_RAIN, Weather.CONDITION_HEAVY_RAIN, Weather.CONDITION_SHOWERS,
             Weather.CONDITION_LIGHT_SHOWERS, Weather.CONDITION_HEAVY_SHOWERS, Weather.CONDITION_SCATTERED_SHOWERS,
             Weather.CONDITION_DRIZZLE, Weather.CONDITION_CHANCE_OF_SHOWERS, Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN,
             Weather.CONDITION_FREEZING_RAIN, Weather.CONDITION_UNKNOWN_PRECIPITATION],
            [Weather.CONDITION_THUNDERSTORMS, Weather.CONDITION_SCATTERED_THUNDERSTORMS, Weather.CONDITION_CHANCE_OF_THUNDERSTORMS,
             Weather.CONDITION_TROPICAL_STORM, Weather.CONDITION_HURRICANE, Weather.CONDITION_TORNADO, Weather.CONDITION_SQUALL],
            [Weather.CONDITION_SNOW, Weather.CONDITION_LIGHT_SNOW, Weather.CONDITION_HEAVY_SNOW, Weather.CONDITION_FLURRIES,
             Weather.CONDITION_WINTRY_MIX, Weather.CONDITION_RAIN_SNOW, Weather.CONDITION_LIGHT_RAIN_SNOW, Weather.CONDITION_HEAVY_RAIN_SNOW,
             Weather.CONDITION_SLEET, Weather.CONDITION_ICE, Weather.CONDITION_ICE_SNOW, Weather.CONDITION_HAIL,
             Weather.CONDITION_CHANCE_OF_SNOW, Weather.CONDITION_CHANCE_OF_RAIN_SNOW, Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW,
             Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW]
        ];
        for (var i = 0; i < groups.size(); i++) {
            if ((groups[i] as Array).indexOf(cond) >= 0) { return i; }
        }
        return 6;   // fog, haze, mist, smoke, dust, sand, ash, unknown
    }

    // Weather icon about 22x18, centered at (x, y).
    private function weatherIcon(dc as Graphics.Dc, kind as Number, x as Number, y as Number, c as Number, c2 as Number) as Void {
        if (kind == 0) {
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 5);
            dc.setPenWidth(2);
            for (var a = 0; a < 8; a++) {
                var r = a * Math.PI / 4;
                dc.drawLine(x + (8 * Math.cos(r)).toNumber(), y + (8 * Math.sin(r)).toNumber(),
                            x + (11 * Math.cos(r)).toNumber(), y + (11 * Math.sin(r)).toNumber());
            }
            dc.setPenWidth(1);
            return;
        }
        if (kind == 1) {
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + 4, y - 4, 5);
        }
        if (kind == 6) {
            dc.setColor(c2, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            for (var i = 0; i < 3; i++) {
                dc.drawLine(x - 10 + i * 2, y - 5 + i * 5, x + 10 - i * 2, y - 5 + i * 5);
            }
            dc.setPenWidth(1);
            return;
        }
        // Cloud.
        dc.setColor(c2, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y + 1, 5);
        dc.fillCircle(x + 1, y - 2, 6);
        dc.fillCircle(x + 7, y + 2, 4);
        dc.fillRectangle(x - 5, y + 1, 12, 5);
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        if (kind == 3) {
            for (var i = 0; i < 3; i++) { dc.drawLine(x - 5 + i * 5, y + 8, x - 7 + i * 5, y + 12); }
        } else if (kind == 4) {
            dc.fillPolygon([[x + 1, y + 6], [x - 3, y + 12], [x, y + 12], [x - 2, y + 16], [x + 4, y + 10], [x + 1, y + 10]]);
        } else if (kind == 5) {
            for (var i = 0; i < 3; i++) { dc.fillCircle(x - 5 + i * 5, y + 10 + (i % 2) * 2, 1); }
        }
    }

    // Header row: phone link on the left, weather on the right.
    private function header(dc as Graphics.Dc, y as Number, c as Number, c2 as Number, off as Number, hlColor as Number) as Void {
        bluetooth(dc, 44, y, System.getDeviceSettings().phoneConnected ? c2 : off, !System.getDeviceSettings().phoneConnected);
        var w = weather();
        if (w == null) {
            // Diagnostic: the watch gave the face no weather.
            dc.setColor(off, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w - 36, y - dc.getFontHeight(_fSmall) / 2, _fSmall, "--°", Graphics.TEXT_JUSTIFY_RIGHT);
            return;
        }
        var right = _w - 36;
        var fh = dc.getFontHeight(_fSmall);
        var ty = y - fh / 2;
        // Right to left: high/low (dim), current temperature, icon.
        var x = right;
        if (!(w[2] as String).equals("")) {
            dc.setColor(hlColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, ty, _fSmall, w[2] as String, Graphics.TEXT_JUSTIFY_RIGHT);
            x -= dc.getTextWidthInPixels(w[2] as String, _fSmall) + 8;
        }
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, ty, _fSmall, w[1] as String, Graphics.TEXT_JUSTIFY_RIGHT);
        x -= dc.getTextWidthInPixels(w[1] as String, _fSmall) + 14;
        weatherIcon(dc, w[0] as Number, x, y, c, c2);
    }

    // Bluetooth rune, about 16px tall, centered at (x, y). Crossed out when the phone is gone.
    private function bluetooth(dc as Graphics.Dc, x as Number, y as Number, c as Number, cross as Boolean) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x, y - 8, x, y + 8);
        dc.drawLine(x, y - 8, x + 5, y - 4);
        dc.drawLine(x + 5, y - 4, x - 5, y + 4);
        dc.drawLine(x, y + 8, x + 5, y + 4);
        dc.drawLine(x + 5, y + 4, x - 5, y - 4);
        if (cross) {
            dc.drawLine(x - 8, y + 9, x + 8, y - 9);
        }
        dc.setPenWidth(1);
    }

    // ---------- pieces ----------

    // Heart, battery gauge, steps across the lower third.
    private function stats(dc as Graphics.Dc, y as Number, color as Number, warn as Number, dim as Number) as Void {
        var cols = [_w / 2 - 92, _w / 2, _w / 2 + 92];
        var bat = battery();
        var vals = [heartRate(), bat.toString(), steps()];
        for (var i = 0; i < 3; i++) {
            var c = (i == 1 && bat <= 20) ? warn : color;
            var x = cols[i] as Number;
            if (i == 1) {
                batteryGauge(dc, x, y + 1, bat, c, dim);
            } else {
                icon(dc, i, x, y, c);
            }
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + 14, _fSmall, vals[i] as String, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // A five-cell battery, about 34x14, centered at x.
    private function batteryGauge(dc as Graphics.Dc, x as Number, y as Number, pct as Number, c as Number, dim as Number) as Void {
        var w = 30;
        var h = 13;
        var x0 = x - w / 2 - 2;
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x0, y, w, h);
        dc.fillRectangle(x0 + w, y + 4, 3, h - 8);
        var cells = (pct + 19) / 20;
        for (var i = 0; i < 5; i++) {
            dc.setColor(i < cells ? c : dim, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + 2 + i * 5 + (i > 0 ? i : 0), y + 2, 5, h - 4);
        }
    }

    // 0 heart, 2 footprints; centered at x, about 16px tall from y.
    private function icon(dc as Graphics.Dc, kind as Number, x as Number, y as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        if (kind == 0) {
            dc.fillCircle(x - 4, y + 4, 5);
            dc.fillCircle(x + 4, y + 4, 5);
            dc.fillPolygon([[x - 9, y + 6], [x + 9, y + 6], [x, y + 15]]);
        } else {
            dc.fillEllipse(x - 4, y + 5, 3, 6);
            dc.fillEllipse(x + 4, y + 9, 3, 6);
        }
    }

    // Now playing, sent by the phone companion: {"t" title, "a" artist, "p" playing}.
    // Draws nothing when there's no music info.
    private function nowPlaying(dc as Graphics.Dc, y as Number, twoLines as Boolean, tColor as Number, aColor as Number, mark as Number) as Void {
        var np = Application.Storage.getValue("np");
        if (!(np instanceof Dictionary)) {
            np = demoMusic();
            if (np == null) { return; }
        }
        var title = np["t"];
        var artist = np["a"];
        var playing = np["p"] == true;
        if (!(title instanceof String) || title.length() == 0) { return; }
        var cx = _w / 2;
        var maxW = _w - 70;
        // Play/pause mark.
        dc.setColor(mark, Graphics.COLOR_TRANSPARENT);
        var my = y + dc.getFontHeight(_fSmall) / 2 - 1;
        var mx = 34;
        if (playing) {
            dc.fillPolygon([[mx, my - 6], [mx + 9, my], [mx, my + 6]]);
        } else {
            dc.fillRectangle(mx, my - 6, 3, 12);
            dc.fillRectangle(mx + 6, my - 6, 3, 12);
        }
        if (twoLines) {
            dc.setColor(tColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 6, y, _fSmall, fit(dc, title.toUpper(), maxW - 12), Graphics.TEXT_JUSTIFY_CENTER);
            if (artist instanceof String) {
                dc.setColor(aColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx + 6, y + dc.getFontHeight(_fSmall) - 6, _fSmall, fit(dc, artist.toUpper(), maxW - 12), Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else {
            var line = (artist instanceof String) ? artist + " - " + title : title;
            dc.setColor(tColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 6, y, _fSmall, fit(dc, line.toUpper(), maxW - 12), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Trims text to fit the width, ending in "..".
    private function fit(dc as Graphics.Dc, text as String, maxW as Number) as String {
        if (dc.getTextWidthInPixels(text, _fSmall) <= maxW) { return text; }
        var n = text.length();
        while (n > 1 && dc.getTextWidthInPixels(text.substring(0, n) + "..", _fSmall) > maxW) {
            n -= 1;
        }
        return text.substring(0, n) + "..";
    }

    // Sample track so the layout can be judged in the simulator. Stripped from release builds.
    (:debug)
    private function demoMusic() as Dictionary? {
        return {"t" => "Never Fade Away", "a" => "SAMURAI", "p" => true};
    }

    (:release)
    private function demoMusic() as Dictionary? {
        return null;
    }

    // One usage ring: a rectangle with cut corners, inset from the edge, filled
    // clockwise from top center by pct. dash > 0 draws it as dashes (Wasteland).
    private function ring(dc as Graphics.Dc, inset as Number, pen as Number, cut as Number, pct as Number, stale as Boolean,
                          on as Number, warn as Number, track as Number, dim as Number, dash as Number, gap as Number) as Void {
        var a = inset;
        var r = _w - inset;
        var b = _h - inset;
        var cx = _w / 2;
        var pts = [[cx, a], [r - cut, a], [r, a + cut], [r, b - cut], [r - cut, b],
                   [a + cut, b], [a, b - cut], [a, a + cut], [a + cut, a], [cx, a]];
        var lens = new [pts.size() - 1];
        var total = 0.0;
        for (var i = 0; i < lens.size(); i++) {
            var p0 = pts[i] as Array<Number>;
            var p1 = pts[i + 1] as Array<Number>;
            var dx = (p1[0] - p0[0]).toFloat();
            var dy = (p1[1] - p0[1]).toFloat();
            lens[i] = Math.sqrt(dx * dx + dy * dy);
            total += lens[i] as Float;
        }
        dc.setPenWidth(pen);
        // Track.
        path(dc, pts, lens, 0.0, total, track, dash, gap);
        if (pct <= 0) {
            dc.setPenWidth(1);
            return;
        }
        var color = stale ? dim : (pct >= 80 ? warn : on);
        var end = total * (pct > 100 ? 100 : pct) / 100.0;
        path(dc, pts, lens, 0.0, end, color, dash, gap);
        // Bright head at the fill point.
        if (!stale && pct < 100) {
            var hp = pointAt(pts, lens, end);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(hp[0], hp[1], pen / 2 + 2);
        }
        dc.setPenWidth(1);
    }

    // Draws the stretch of the polyline between distances d0 and d1, solid or dashed.
    private function path(dc as Graphics.Dc, pts as Array, lens as Array, d0 as Float, d1 as Float, color as Number, dash as Number, gap as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (dash <= 0) {
            segment(dc, pts, lens, d0, d1);
            return;
        }
        var d = d0;
        while (d < d1) {
            var e = d + dash;
            segment(dc, pts, lens, d, e > d1 ? d1 : e);
            d = e + gap;
        }
    }

    private function segment(dc as Graphics.Dc, pts as Array, lens as Array, d0 as Float, d1 as Float) as Void {
        var start = 0.0;
        for (var i = 0; i < lens.size(); i++) {
            var len = lens[i] as Float;
            var stop = start + len;
            if (stop > d0 && start < d1) {
                var t0 = (d0 > start) ? (d0 - start) / len : 0.0;
                var t1 = (d1 < stop) ? (d1 - start) / len : 1.0;
                var p0 = pts[i] as Array<Number>;
                var p1 = pts[i + 1] as Array<Number>;
                dc.drawLine(p0[0] + ((p1[0] - p0[0]) * t0).toNumber(), p0[1] + ((p1[1] - p0[1]) * t0).toNumber(),
                            p0[0] + ((p1[0] - p0[0]) * t1).toNumber(), p0[1] + ((p1[1] - p0[1]) * t1).toNumber());
            }
            start = stop;
        }
    }

    private function pointAt(pts as Array, lens as Array, d as Float) as Array<Number> {
        var start = 0.0;
        for (var i = 0; i < lens.size(); i++) {
            var len = lens[i] as Float;
            if (d <= start + len) {
                var t = (d - start) / len;
                var p0 = pts[i] as Array<Number>;
                var p1 = pts[i + 1] as Array<Number>;
                return [p0[0] + ((p1[0] - p0[0]) * t).toNumber(), p0[1] + ((p1[1] - p0[1]) * t).toNumber()];
            }
            start += len;
        }
        return pts[pts.size() - 1] as Array<Number>;
    }
}
