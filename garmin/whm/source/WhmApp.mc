import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class WhmApp extends Application.AppBase {

    var mModel as WhmModel;
    var mTimer as Timer.Timer;
    var mSensorsActive as Boolean = false;
    var mSession = null;
    var mFieldRetention = null;
    var mFieldRounds = null;
    var mFieldAvgRetention = null;
    var mLastState as Number = STATE_START;
    var mLastRoundCount as Number = 0;

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
        if (mSession != null) {
            _stopRecording();
        }
    }

    function onTick() as Void {
        mModel.tick(System.getTimer());
        var s = mModel.state;
        if (s == STATE_BREATHING || s == STATE_RETENTION || s == STATE_RECOVERY) {
            _startSensors();
        } else {
            _stopSensors();
        }
        // Detect state transitions for recording lifecycle
        if (s != mLastState) {
            if (mLastState == STATE_START && s == STATE_BREATHING) {
                _startRecording();
            } else if (s == STATE_STOPPED && mSession != null) {
                _stopRecording();
            }
            mLastState = s;
        }
        // Detect new lap (retention round completed)
        var rounds = mModel.retentionTimes.size();
        if (rounds > mLastRoundCount && mSession != null) {
            _addLap();
            mLastRoundCount = rounds;
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

    function _startRecording() as Void {
        mSession = ActivityRecording.createSession({
            :name => "WHM",
            :sport => Activity.SPORT_TRAINING,
            :subSport => Activity.SUB_SPORT_BREATHING
        });
        mFieldRetention = mSession.createField("retention_ms", 0,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "ms"});
        mFieldRounds = mSession.createField("rounds", 1,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        mFieldAvgRetention = mSession.createField("avg_retention_ms", 2,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ms"});
        mLastRoundCount = 0;
        mSession.start();
    }

    function _stopRecording() as Void {
        var times = mModel.retentionTimes;
        var count = times.size();
        mFieldRounds.setData(count);
        if (count > 0) {
            var sum = 0;
            for (var i = 0; i < count; i++) {
                sum += times[i] as Number;
            }
            mFieldAvgRetention.setData(sum / count);
        } else {
            mFieldAvgRetention.setData(0);
        }
        mSession.stop();
        mSession.save();
        mSession = null;
        mFieldRetention = null;
        mFieldRounds = null;
        mFieldAvgRetention = null;
    }

    function _addLap() as Void {
        var times = mModel.retentionTimes;
        var latest = times[times.size() - 1] as Number;
        mFieldRetention.setData(latest);
        mSession.addLap();
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
