import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class WhmDelegate extends WatchUi.BehaviorDelegate {

    var mModel as WhmModel;

    function initialize(model as WhmModel) {
        BehaviorDelegate.initialize();
        mModel = model;
    }

    // Consume screen taps so they don't trigger onSelect
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    // START/STOP button — start session or stop session
    function onSelect() as Boolean {
        var now = System.getTimer();
        var state = mModel.state;
        if (state == STATE_START) {
            mModel.switchState(STATE_BREATHING, now);
        } else if (state == STATE_BREATHING || state == STATE_RETENTION || state == STATE_RECOVERY) {
            mModel.switchState(STATE_STOPPED, now);
        } else if (state == STATE_STOPPED) {
            var phase = mModel.phase;
            if (phase == PHASE_STOPPED_OPTIONS) {
                var app = getApp();
                var choice = mModel.stoppedOption;
                if (choice == STOPPED_OPTION_SAVE) {
                    app._saveRecording();
                    mModel.showStoppedResults(now);
                } else if (choice == STOPPED_OPTION_DELETE) {
                    app._discardRecording();
                    mModel.showStoppedResults(now);
                } else {
                    // CONTINUE — keep FIT session open, just go back to BREATHING
                    mModel.switchState(STATE_BREATHING, now);
                }
            } else {
                mModel.switchState(STATE_START, now);
            }
        }
        return true;
    }

    // BACK/LAP button — advance phases during activity, exit app otherwise
    function onBack() as Boolean {
        var now = System.getTimer();
        var state = mModel.state;
        var phase = mModel.phase;
        if (state == STATE_BREATHING) {
            mModel.switchState(STATE_RETENTION, now);
            return true;
        } else if (state == STATE_RETENTION && phase == PHASE_RETENTION_IDLE) {
            mModel.switchState(STATE_RECOVERY, now);
            return true;
        } else if (state == STATE_STOPPED) {
            // Let system exit the app
            return false;
        }
        // START screen: let system exit the app
        return false;
    }

    // DOWN button — page through results / move options highlight down
    function onNextPage() as Boolean {
        if (mModel.state == STATE_STOPPED) {
            var phase = mModel.phase;
            if (phase == PHASE_STOPPED_IDLE) {
                mModel.nextResultsPage();
                return true;
            } else if (phase == PHASE_STOPPED_OPTIONS) {
                mModel.nextStoppedOption();
                return true;
            }
        }
        return false;
    }

    // UP button — page back through results / move options highlight up
    function onPreviousPage() as Boolean {
        if (mModel.state == STATE_STOPPED) {
            var phase = mModel.phase;
            if (phase == PHASE_STOPPED_IDLE) {
                mModel.prevResultsPage();
                return true;
            } else if (phase == PHASE_STOPPED_OPTIONS) {
                mModel.prevStoppedOption();
                return true;
            }
        }
        return false;
    }
}
