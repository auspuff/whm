import Toybox.Application;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class WhmApp extends Application.AppBase {

    var mModel as WhmModel;
    var mTimer as Timer.Timer;
    var mSensorsActive as Boolean = false;

    function initialize() {
        AppBase.initialize();
        mModel = new WhmModel();
        mTimer = new Timer.Timer();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        mTimer.start(method(:onTick), 50, true);
    }

    function onStop(state as Lang.Dictionary?) as Void {
        mTimer.stop();
        _stopSensors();
    }

    function onTick() as Void {
        mModel.tick(System.getTimer());
        var s = mModel.state;
        if (s == STATE_BREATHING || s == STATE_RETENTION || s == STATE_RECOVERY) {
            _startSensors();
        } else {
            _stopSensors();
        }
        WatchUi.requestUpdate();
    }

    function onSensor(info as Sensor.Info) as Void {
        var hr = 0;
        var spo2 = 0;
        if (info.heartRate != null) {
            hr = info.heartRate as Number;
        }
        if (info has :oxygenSaturation && info.oxygenSaturation != null) {
            spo2 = info.oxygenSaturation as Number;
        }
        mModel.addSensorSample(hr, spo2);
    }

    function _startSensors() as Void {
        if (!mSensorsActive) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_PULSE_OXIMETRY]);
            Sensor.enableSensorEvents(method(:onSensor));
            mSensorsActive = true;
        }
    }

    function _stopSensors() as Void {
        if (mSensorsActive) {
            Sensor.enableSensorEvents(null);
            mSensorsActive = false;
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new WhmView(mModel), new WhmDelegate(mModel)];
    }
}

function getApp() as WhmApp {
    return Application.getApp() as WhmApp;
}
