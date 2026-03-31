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
            mModel.switchState(STATE_START, now);
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

    // DOWN button — page through results when stopped
    function onNextPage() as Boolean {
        if (mModel.state == STATE_STOPPED && mModel.phase == PHASE_STOPPED_IDLE) {
            mModel.nextResultsPage();
            return true;
        }
        return false;
    }

    // UP button — page back through results when stopped
    function onPreviousPage() as Boolean {
        if (mModel.state == STATE_STOPPED && mModel.phase == PHASE_STOPPED_IDLE) {
            mModel.prevResultsPage();
            return true;
        }
        return false;
    }
}
