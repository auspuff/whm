import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class WhmDelegate extends WatchUi.BehaviorDelegate {

    var mModel as WhmModel;

    function initialize(model as WhmModel) {
        BehaviorDelegate.initialize();
        mModel = model;
    }

    // START/STOP button or screen tap — advance to next phase
    function onSelect() as Boolean {
        _handleAdvance(System.getTimer());
        return true;
    }

    // DOWN button — page through results when stopped, otherwise advance
    function onNextPage() as Boolean {
        if (mModel.state == STATE_STOPPED && mModel.phase == PHASE_STOPPED_IDLE) {
            mModel.nextResultsPage();
            return true;
        }
        _handleAdvance(System.getTimer());
        return true;
    }

    // UP button — page back through results when stopped
    function onPreviousPage() as Boolean {
        if (mModel.state == STATE_STOPPED && mModel.phase == PHASE_STOPPED_IDLE) {
            mModel.prevResultsPage();
            return true;
        }
        return false;
    }

    // BACK button — stop session or exit app
    function onBack() as Boolean {
        return _handleBack(System.getTimer());
    }

    // ── Button logic ──────────────────────────────────────────────────────────

    // Forward advance through phases: start → breathing → retention → recovery
    function _handleAdvance(now as Number) as Void {
        var state = mModel.state;
        var phase = mModel.phase;
        if (state == STATE_START) {
            mModel.switchState(STATE_BREATHING, now);
        } else if (state == STATE_BREATHING) {
            mModel.switchState(STATE_RETENTION, now);
        } else if (state == STATE_RETENTION && phase == PHASE_RETENTION_IDLE) {
            mModel.switchState(STATE_RECOVERY, now);
        } else if (state == STATE_STOPPED) {
            mModel.switchState(STATE_START, now);
        }
    }

    // Returns true if handled, false to let the system exit the app
    function _handleBack(now as Number) as Boolean {
        var state = mModel.state;
        if (state == STATE_BREATHING || state == STATE_RETENTION || state == STATE_RECOVERY) {
            mModel.switchState(STATE_STOPPED, now);
            return true;
        }
        return false;
    }
}
