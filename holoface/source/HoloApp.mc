import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Watch face entry. The background service fetches Claude usage every 5 minutes
// (the shortest interval Garmin allows) and receives now-playing messages from the
// Holo Link phone app; both come back here to be stored.
(:background)
class HoloApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
            if (Background has :registerForPhoneAppMessageEvent) {
                Background.registerForPhoneAppMessageEvent();
            }
        }
        return [new HoloView()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new UsageService()];
    }

    // The background sends {"usage": {...}}, {"np": {...}}, {"wx": {...}}, {"sm": {...}} or {"err": code}.
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            if (data.hasKey("np")) {
                Application.Storage.setValue("np", data["np"]);
            } else if (data.hasKey("sm")) {
                var sm = data["sm"] as Dictionary;
                sm["got"] = Time.now().value();
                Application.Storage.setValue("sm", sm);
            } else if (data.hasKey("wx")) {
                var wx = data["wx"] as Dictionary;
                wx["got"] = Time.now().value();
                Application.Storage.setValue("wx", wx);
            } else if (data.hasKey("usage")) {
                var u = data["usage"] as Dictionary;
                u["got"] = Time.now().value();
                Application.Storage.setValue("usage", u);
                Application.Storage.deleteValue("usageErr");
            } else if (data.hasKey("err")) {
                Application.Storage.setValue("usageErr", data["err"]);
            }
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
