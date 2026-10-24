import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// Background work for the face:
//  - every 5 minutes, fetch Claude usage through the phone's Garmin Connect app:
//    {"five_hour": 23.5, "seven_day": 41.2, "five_reset": <epoch>, "seven_reset": <epoch>, "updated": <epoch>}
//    from the URL in the face's settings (Android only allows https here);
//  - whenever the Holo Link phone app sends a track: {"t": title, "a": artist, "p": playing},
//    or weather: {"wx": {"c": WMO code, "t": now C, "hi": high C, "lo": low C}}.
(:background)
class UsageService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var url = Application.Properties.getValue("usageUrl");
        if (!(url instanceof String) || url.length() == 0) {
            Background.exit(null);
            return;
        }
        Communications.makeWebRequest(url, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            // GitHub serves the gist as text/plain, which Garmin Connect on Android refuses to hand
            // over as JSON, so it's fetched as text and the numbers are read out here.
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        }, method(:onReceive));
    }

    function onReceive(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof String) {
            Background.exit({"usage" => {
                "s" => num(data, "five_hour"), "w" => num(data, "seven_day"),
                "sr" => num(data, "five_reset"), "wr" => num(data, "seven_reset"),
                "t" => num(data, "updated")
            }});
        } else {
            Background.exit({"err" => code});
        }
    }

    // Reads the number after "key": in a flat JSON string; null if missing or null.
    function num(text as String, key as String) as Number or Null {
        var at = text.find("\"" + key + "\":");
        if (at == null) { return null; }
        var rest = text.substring(at + key.length() + 3, text.length()) as String;
        while (rest.length() > 0 && rest.substring(0, 1).equals(" ")) {
            rest = rest.substring(1, rest.length()) as String;
        }
        var end = rest.length();
        var comma = rest.find(",");
        var brace = rest.find("}");
        if (comma != null && comma < end) { end = comma; }
        if (brace != null && brace < end) { end = brace; }
        var v = (rest.substring(0, end) as String).toFloat();
        return (v == null) ? null : v.toNumber();
    }

    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        var d = msg.data;
        if (d instanceof Dictionary && d.hasKey("wx")) {
            Background.exit({"wx" => d["wx"]});
        } else if (d instanceof Dictionary) {
            Background.exit({"np" => d});
        } else {
            Background.exit(null);
        }
    }
}
