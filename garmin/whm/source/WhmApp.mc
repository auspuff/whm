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
    var mSession as ActivityRecording.Session? = null;
    var mFieldRetention as FitContributor.Field? = null;
    var mFieldRounds as FitContributor.Field? = null;
    var mFieldAvgRetention as FitContributor.Field? = null;
    var mFieldSpo2 as FitContributor.Field? = null;
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
            _saveRecording();
        }
    }

    function onTick() as Void {
        mModel.tick(System.getTimer());
        var s = mModel.state;
        // Detect state transitions for recording lifecycle
        if (s != mLastState) {
            if (mLastState == STATE_START && s == STATE_BREATHING) {
                _startRecording();
            } else if (mLastState == STATE_STOPPED && s == STATE_START
                    && mSession != null) {
                // Left stopped without picking Save/Delete
                // (empty-data auto-return, or SELECT during shrink) — discard
                // so we don't leak a session that would crash the next start.
                _discardRecording();
            }
            // STOPPED → BREATHING (Continue) leaves the open session intact.
            mLastState = s;
        }
        // Sensors stay on as long as the FIT session is recording
        if (mSession != null) {
            _startSensors();
        } else {
            _stopSensors();
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
        var spo2Field = mFieldSpo2;
        if (spo2Field != null && spo2 > 0) {
            spo2Field.setData(spo2);
        }
    }

    function _startRecording() as Void {
        if (!(Toybox has :ActivityRecording)) { return; }
        var session = ActivityRecording.createSession({
            :name => "WHM",
            :sport => Activity.SPORT_TRAINING,
            :subSport => Activity.SUB_SPORT_BREATHING
        });
        mSession = session;
        mFieldRetention = session.createField("retention_ms", 0,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "ms"});
        mFieldRounds = session.createField("rounds", 1,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        mFieldAvgRetention = session.createField("avg_retention_ms", 2,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ms"});
        mFieldSpo2 = session.createField("spo2", 3,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%"});
        mLastRoundCount = 0;
        session.start();
    }

    function _saveRecording() as Void {
        var session = mSession;
        if (session == null) { return; }
        var times = mModel.retentionTimes;
        var count = times.size();
        var rounds = mFieldRounds;
        if (rounds != null) { rounds.setData(count); }
        var avg = mFieldAvgRetention;
        if (avg != null) {
            if (count > 0) {
                var sum = 0;
                for (var i = 0; i < count; i++) {
                    sum += times[i] as Number;
                }
                avg.setData(sum / count);
            } else {
                avg.setData(0);
            }
        }
        if (session.isRecording()) {
            session.stop();
            session.save();
        }
        _clearSession();
    }

    function _discardRecording() as Void {
        var session = mSession;
        if (session == null) { return; }
        if (session.isRecording()) {
            session.stop();
            if (session has :discard) {
                session.discard();
            } else {
                session.save();
            }
        }
        _clearSession();
    }

    function _clearSession() as Void {
        mSession = null;
        mFieldRetention = null;
        mFieldRounds = null;
        mFieldAvgRetention = null;
        mFieldSpo2 = null;
        mLastRoundCount = 0;
    }

    function _addLap() as Void {
        var session = mSession;
        if (session == null) { return; }
        var retention = mFieldRetention;
        if (retention != null) {
            var times = mModel.retentionTimes;
            var latest = times[times.size() - 1] as Number;
            retention.setData(latest);
        }
        session.addLap();
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
