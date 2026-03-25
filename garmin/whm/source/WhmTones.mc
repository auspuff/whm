import Toybox.Attention;
import Toybox.Lang;

// Static helpers that wrap Attention API.
// Each state transition triggers a distinctly pitched tone + vibration.
module WhmTones {

    // Called from switchState() with the new state value.
    function playForState(newState as Number) as Void {
        if (newState == STATE_BREATHING) {
            _playBreathingStart();
        } else if (newState == STATE_RETENTION) {
            _playRetentionStart();
        } else if (newState == STATE_RECOVERY) {
            _playRecoveryStart();
        } else if (newState == STATE_STOPPED) {
            _playStopped();
        }
    }

    // Breathing start — low-mid tone
    function _playBreathingStart() as Void {
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_START);
        }
        _vibrate(200);
    }

    // Retention start — high tone (distinct from breathing)
    function _playRetentionStart() as Void {
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_LOUD_BEEP);
        }
        _vibrate(200);
    }

    // Recovery start — same low-mid as breathing
    function _playRecoveryStart() as Void {
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_START);
        }
        _vibrate(200);
    }

    // Session stopped — low, longer tone
    function _playStopped() as Void {
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_STOP);
        }
        _vibrate(500);
    }

    // Recovery countdown tick — vibration only
    function playCountdownTick() as Void {
        _vibrate(50);
    }

    // Recovery countdown final second — vibration only
    function playCountdownFinal() as Void {
        _vibrate(200);
    }

    function _vibrate(durationMs as Number) as Void {
        if (Attention has :vibrate) {
            var profile = [new Attention.VibeProfile(100, durationMs)] as Array<Attention.VibeProfile>;
            Attention.vibrate(profile);
        }
    }
}
