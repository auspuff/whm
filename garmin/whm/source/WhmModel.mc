import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// ── State constants ──────────────────────────────────────────────────────────
const STATE_START     = 0;
const STATE_BREATHING = 1;
const STATE_RETENTION = 2;
const STATE_RECOVERY  = 3;
const STATE_STOPPED   = 4;
const STATE_READY     = 5;  // triangle shown, waiting for user to press START

// ── Phase constants ──────────────────────────────────────────────────────────
const PHASE_TRANSITION     = 0;
const PHASE_LOOP           = 1;
const PHASE_HOLD           = 2;
const PHASE_RETENTION_SEQ  = 3;
const PHASE_RETENTION_IDLE = 4;
const PHASE_STOPPED_SHRINK  = 5;
const PHASE_STOPPED_IDLE    = 6;
const PHASE_STOPPED_OPTIONS = 7;

const STOPPED_OPTION_SAVE     = 0;
const STOPPED_OPTION_DELETE   = 1;
const STOPPED_OPTION_CONTINUE = 2;

// ── Method constants ─────────────────────────────────────────────────────────
const METHOD_WHM   = 0;
const METHOD_478   = 1;
const METHOD_COUNT = 2;

// ── 4-7-8 sub-phase constants ────────────────────────────────────────────────
const SUBPHASE_INHALE = 0;
const SUBPHASE_HOLD   = 1;
const SUBPHASE_EXHALE = 2;

// ── Timing / animation constants ─────────────────────────────────────────────
const TRANS_MS            = 2000;
const RECOVERY_TRANS_MS   = 3000;
const SMALL_SCALE         = 0.25f;
const BREATH_COUNT        = 30;
const RECOVERY_HOLD_MS    = 15000;
const RECOVERY_SMALL_WAIT = 6000;
const STOPPED_SHRINK_MS   = 1000;
const START_GROW_MS       = 1200;
const START_MORPH_MS      = 2000;
const IDLE_SCALE          = 0.3f;
const INTRO_SCALE         = 0.005f;
const RETENTION_HOLD_MS   = 1000;

// ── 4-7-8 timing ─────────────────────────────────────────────────────────────
const FOUR_SEVEN_EIGHT_INHALE_MS     = 4000;
const FOUR_SEVEN_EIGHT_HOLD_MS       = 7000;
const FOUR_SEVEN_EIGHT_EXHALE_MS     = 8000;
const FOUR_SEVEN_EIGHT_CYCLE_MS      = 19000;
const FOUR_SEVEN_EIGHT_TARGET_CYCLES = 4;

// ── Polygon constants ────────────────────────────────────────────────────────
const NUM_POINTS    = 120;
const SMOOTH_WINDOW = 2;
const BIG_FLOAT     = 999999.0f;
const TINY_FLOAT    = 0.0000000001f;

class WhmModel {

    // ── State machine ─────────────────────────────────────────────────────────
    var state     as Number = STATE_START;
    var prevState as Number = STATE_START;
    var phase     as Number = PHASE_TRANSITION;

    // ── Method selection (persists across sessions) ─────────────────────────
    var method as Number = METHOD_WHM;

    // ── 4-7-8 per-cycle tracking ─────────────────────────────────────────────
    var breathSubPhase        as Number = SUBPHASE_INHALE;
    var subPhaseSecsRemaining as Number = 0;
    var cyclesCompleted       as Number = 0;
    var prevCycleElapsed      as Number = 0;
    var prevSubPhase          as Number = SUBPHASE_INHALE;

    // ── Animation interpolation ───────────────────────────────────────────────
    var morphCurrent as Float = 1.0f;
    var morphFrom    as Float = 1.0f;
    var morphTo      as Float = 0.0f;
    var scaleCurrent as Float = INTRO_SCALE;
    var scaleFrom    as Float = INTRO_SCALE;
    var scaleTo      as Float = IDLE_SCALE;
    var pillT        as Float = 0.0f;
    var pillFrom     as Float = 0.0f;

    // ── Timing (ms from System.getTimer()) ───────────────────────────────────
    var phaseStartMs         as Number = 0;
    var retentionFinishMs    as Number = 0;
    var cycleElapsedMs       as Number = 0;
    var retentionIdleStartMs as Number = 0;

    // ── Session data ──────────────────────────────────────────────────────────
    var retentionTimes as Array = [];
    var lastBeepSec        as Number = -1;
    var lastRetentionSecs  as Number = 0;
    var sessionStartMs     as Number = 0;
    var sessionDurationSecs as Number = 0;

    // ── Sensor data (parallel arrays — same index = same sample) ──────────────
    var hrSamples    as Array = [];
    var spo2Samples  as Array = [];
    var sensorStartMs as Number = 0;
    var sampleSkip   as Number = 0;
    var sampleRate   as Number = 1;
    const MAX_SAMPLES = 600;

    // ── Results paging (0 = times, 1 = HR, 2 = SpO2) ───────────────────────
    var resultsPage as Number = 0;

    // ── Stopped-options highlight (0 = Save, 1 = Delete, 2 = Continue) ─────
    var stoppedOption as Number = 0;

    // ── Stopped phase ─────────────────────────────────────────────────────────
    var stoppedInitRadius as Float = -1.0f;
    var stoppedInitMorph  as Float = -1.0f;

    // ── Precomputed polygon tables ────────────────────────────────────────────
    var polyAngles   as Array;
    var polyCos      as Array;
    var polySin      as Array;
    var polyTriRadii as Array;
    var polygon      as Array;

    // Triangle vertices (initialized in constructor since const arrays can be tricky)
    var triX as Array;
    var triY as Array;

    function initialize() {
        triX = [-0.7f, -0.7f, 1.0f];
        triY = [-1.0f,  1.0f, 0.0f];

        polyAngles   = new [NUM_POINTS];
        polyCos      = new [NUM_POINTS];
        polySin      = new [NUM_POINTS];
        polyTriRadii = new [NUM_POINTS];
        polygon      = new [NUM_POINTS];

        for (var i = 0; i < NUM_POINTS; i++) {
            polyAngles[i]   = 0.0f;
            polyCos[i]      = 1.0f;
            polySin[i]      = 0.0f;
            polyTriRadii[i] = 1.0f;
            polygon[i]      = [0, 0];
        }

        _buildAngles();
        // Precompute trig from final sorted angles
        for (var i = 0; i < NUM_POINTS; i++) {
            var a = polyAngles[i] as Float;
            polyCos[i] = Math.cos(a).toFloat();
            polySin[i] = Math.sin(a).toFloat();
        }
        _computeSmoothedRadii();

        phaseStartMs = System.getTimer();
    }

    // ── Easing ────────────────────────────────────────────────────────────────

    function easeInOutCubic(t as Float) as Float {
        if (t < 0.5f) {
            return 4.0f * t * t * t;
        }
        var u = -2.0f * t + 2.0f;
        return 1.0f - (u * u * u) / 2.0f;
    }

    function lerp(a as Float, b as Float, t as Float) as Float {
        return a + (b - a) * t;
    }

    // ── Polygon precomputation ────────────────────────────────────────────────

    function _rayEdgeDist(
        dx as Float, dy as Float,
        ax as Float, ay as Float,
        bx as Float, by as Float
    ) as Float {
        var ex    = bx - ax;
        var ey    = by - ay;
        var denom = dx * ey - dy * ex;
        if (denom < 0.0f) { denom = -denom; }
        if (denom < TINY_FLOAT) { return BIG_FLOAT; }
        // Recompute with original sign for correct t and u
        var denomSigned = dx * ey - dy * ex;
        var t = (ax * ey - ay * ex) / denomSigned;
        var u = (ax * dy - ay * dx) / denomSigned;
        if (t > 0.0f && u >= 0.0f && u <= 1.0f) { return t; }
        return BIG_FLOAT;
    }

    function _getTriangleRadius(angle as Float) as Float {
        var dx = Math.cos(angle).toFloat();
        var dy = Math.sin(angle).toFloat();
        var minDist = BIG_FLOAT;
        for (var i = 0; i < 3; i++) {
            var j = (i + 1) % 3;
            var d = _rayEdgeDist(
                dx, dy,
                triX[i] as Float, triY[i] as Float,
                triX[j] as Float, triY[j] as Float
            );
            if (d < minDist) { minDist = d; }
        }
        return minDist;
    }

    function _buildAngles() as Void {
        var vertAngles = new [3];
        for (var i = 0; i < 3; i++) {
            vertAngles[i] = Math.atan2(triY[i] as Float, triX[i] as Float).toFloat();
        }
        // Sort 3 vertex angles ascending
        for (var i = 0; i < 2; i++) {
            for (var j = 0; j < 2 - i; j++) {
                if ((vertAngles[j] as Float) > (vertAngles[j + 1] as Float)) {
                    var tmp = vertAngles[j];
                    vertAngles[j] = vertAngles[j + 1];
                    vertAngles[j + 1] = tmp;
                }
            }
        }

        var twoPi = 6.2831853f;
        var pi    = 3.1415926f;
        var arcFrom = new [3];
        var arcSpan = new [3];
        for (var i = 0; i < 3; i++) {
            var from = vertAngles[i] as Float;
            var to   = vertAngles[(i + 1) % 3] as Float;
            var span = to > from ? to - from : to - from + twoPi;
            arcFrom[i] = from;
            arcSpan[i] = span;
        }

        var remaining = NUM_POINTS - 3;
        var idx = 0;
        for (var a = 0; a < 3; a++) {
            polyAngles[idx] = arcFrom[a] as Float;
            idx++;
            var count = (remaining.toFloat() * ((arcSpan[a] as Float) / twoPi) + 0.5f).toNumber();
            for (var i = 1; i <= count && idx < NUM_POINTS; i++) {
                var ang = (arcFrom[a] as Float) + (i.toFloat() / (count + 1).toFloat()) * (arcSpan[a] as Float);
                if (ang > pi) { ang = ang - twoPi; }
                polyAngles[idx] = ang;
                idx++;
            }
        }
        while (idx < NUM_POINTS) {
            polyAngles[idx] = (polyAngles[idx - 1] as Float) + 0.001f;
            idx++;
        }

        // Insertion sort — O(n) for nearly-sorted data
        for (var i = 1; i < NUM_POINTS; i++) {
            var key = polyAngles[i] as Float;
            var j = i - 1;
            while (j >= 0 && (polyAngles[j] as Float) > key) {
                polyAngles[j + 1] = polyAngles[j];
                j--;
            }
            polyAngles[j + 1] = key;
        }
    }

    function _computeSmoothedRadii() as Void {
        var raw = new [NUM_POINTS];
        for (var i = 0; i < NUM_POINTS; i++) {
            raw[i] = _getTriangleRadius(polyAngles[i] as Float);
        }
        for (var i = 0; i < NUM_POINTS; i++) {
            var sum   = 0.0f;
            var count = 0;
            for (var j = -SMOOTH_WINDOW; j <= SMOOTH_WINDOW; j++) {
                var k = (i + j + NUM_POINTS) % NUM_POINTS;
                sum += raw[k] as Float;
                count++;
            }
            polyTriRadii[i] = sum / count.toFloat();
        }
    }

    // ── Polygon computation (called by View each frame) ───────────────────────

    function computePolygon(cx as Number, cy as Number, r as Float) as Array {
        var scale = scaleCurrent > 0.0f ? scaleCurrent : 0.0f;
        var morph = morphCurrent;
        for (var i = 0; i < NUM_POINTS; i++) {
            var circR  = r;
            var triR   = (polyTriRadii[i] as Float) * r;
            var dist   = lerp(triR, circR, morph) * scale;
            var pt     = polygon[i] as Array;
            pt[0] = (cx + dist * (polyCos[i] as Float)).toNumber();
            pt[1] = (cy + dist * (polySin[i] as Float)).toNumber();
        }
        return polygon;
    }

    // ── Sensor recording ──────────────────────────────────────────────────────

    function addSensorSample(hr as Number, spo2 as Number) as Void {
        if (hrSamples.size() >= MAX_SAMPLES) {
            _downsampleHalf();
        }
        sampleSkip++;
        if (sampleSkip >= sampleRate) {
            sampleSkip = 0;
            hrSamples.add(hr);
            spo2Samples.add(spo2);
        }
    }

    function _downsampleHalf() as Void {
        var newHr = [];
        var newSpo2 = [];
        for (var i = 0; i < hrSamples.size(); i += 2) {
            newHr.add(hrSamples[i]);
            newSpo2.add(spo2Samples[i]);
        }
        hrSamples = newHr;
        spo2Samples = newSpo2;
        sampleRate *= 2;
    }

    function _sensorStats(samples as Array) as Array {
        var min = 999;
        var max = 0;
        var sum = 0;
        var count = 0;
        for (var i = 0; i < samples.size(); i++) {
            var v = samples[i] as Number;
            if (v > 0) {
                if (v < min) { min = v; }
                if (v > max) { max = v; }
                sum += v;
                count++;
            }
        }
        if (count == 0) { return [0, 0, 0]; }
        return [min, max, sum / count];
    }

    function getHrStats() as Array { return _sensorStats(hrSamples); }
    function getSpo2Stats() as Array { return _sensorStats(spo2Samples); }

    // ── Method selection ────────────────────────────────────────────────────

    function nextMethod() as Void {
        method = (method + 1) % METHOD_COUNT;
    }

    function prevMethod() as Void {
        method = (method + METHOD_COUNT - 1) % METHOD_COUNT;
    }

    function getMethodLabel() as String {
        if (method == METHOD_478) { return "4-7-8"; }
        return "WHM";
    }

    function getSubPhaseLabel() as String {
        if (breathSubPhase == SUBPHASE_INHALE) { return "Inhale"; }
        if (breathSubPhase == SUBPHASE_HOLD)   { return "Hold"; }
        return "Exhale";
    }

    // ── Results paging ──────────────────────────────────────────────────────

    function getResultsPageCount() as Number {
        if (method == METHOD_478) { return 1; }
        return 3;
    }

    function nextResultsPage() as Void {
        var n = getResultsPageCount();
        resultsPage = (resultsPage + 1) % n;
    }

    function prevResultsPage() as Void {
        var n = getResultsPageCount();
        resultsPage = (resultsPage + n - 1) % n;
    }

    // ── Stopped-options navigation ──────────────────────────────────────────

    function nextStoppedOption() as Void {
        stoppedOption = (stoppedOption + 1) % 3;
    }

    function prevStoppedOption() as Void {
        stoppedOption = (stoppedOption + 2) % 3;
    }

    function showStoppedResults(nowMs as Number) as Void {
        phase        = PHASE_STOPPED_IDLE;
        phaseStartMs = nowMs;
        resultsPage  = 0;
    }

    // ── State switching ───────────────────────────────────────────────────────

    function switchState(newState as Number, nowMs as Number) as Void {
        if (state == STATE_RETENTION && phase == PHASE_RETENTION_IDLE
                && retentionIdleStartMs > 0) {
            var duration = nowMs - retentionIdleStartMs;
            retentionTimes.add(duration);
            lastRetentionSecs = duration / 1000;
        }

        morphFrom = morphCurrent;
        scaleFrom = scaleCurrent;
        stoppedInitRadius = -1.0f;
        stoppedInitMorph  = -1.0f;
        pillFrom  = pillT;

        prevState     = state;
        state         = newState;
        phase         = PHASE_TRANSITION;
        phaseStartMs  = nowMs;

        WhmTones.playForState(newState);

        switch (newState) {
            case STATE_START:
                morphTo   = 0.0f;
                scaleTo   = IDLE_SCALE;
                morphFrom = 0.0f;
                scaleFrom = 0.0f;
                pillT     = 0.0f;
                retentionTimes = [];
                hrSamples      = [];
                spo2Samples    = [];
                sampleSkip     = 0;
                sampleRate     = 1;
                resultsPage    = 0;
                stoppedOption  = 0;
                sessionStartMs      = 0;
                sessionDurationSecs = 0;
                cyclesCompleted     = 0;
                prevCycleElapsed    = 0;
                prevSubPhase        = SUBPHASE_INHALE;
                break;

            case STATE_READY:
                morphTo = 0.0f;          // triangle
                scaleTo = IDLE_SCALE;    // 30% scale
                pillT   = 0.0f;
                break;

            case STATE_BREATHING:
                morphTo = 1.0f;
                if (method == METHOD_478) {
                    // Ease to a small circle; first inhale grows from there.
                    scaleTo = SMALL_SCALE;
                    // Reset cycle tracking so Continue doesn't trigger a false wrap.
                    prevCycleElapsed = 0;
                    prevSubPhase     = SUBPHASE_EXHALE;
                } else {
                    scaleTo = 1.0f;
                }
                pillT   = 0.0f;
                if (sessionStartMs == 0) {
                    sessionStartMs = nowMs;
                }
                break;

            case STATE_RETENTION: {
                morphTo = 1.0f;
                lastRetentionSecs = 0;
                retentionIdleStartMs = 0;
                var cycleMs = TRANS_MS * 2;
                var remainToSmall = 0;
                if (cycleElapsedMs <= TRANS_MS) {
                    remainToSmall = TRANS_MS - cycleElapsedMs;
                } else {
                    remainToSmall = (cycleMs - cycleElapsedMs) + TRANS_MS;
                }
                retentionFinishMs = remainToSmall;
                phase = PHASE_RETENTION_SEQ;
                break;
            }

            case STATE_RECOVERY:
                morphTo  = 1.0f;
                scaleTo  = 1.0f;
                pillFrom = pillT;
                break;

            case STATE_STOPPED:
                morphTo       = 1.0f;
                morphCurrent  = 1.0f;
                pillT         = 0.0f;
                phase         = PHASE_STOPPED_SHRINK;
                resultsPage   = 0;
                stoppedOption = 0;
                if (sessionStartMs > 0) {
                    sessionDurationSecs = (nowMs - sessionStartMs) / 1000;
                }
                break;
        }
    }

    // ── Main tick ─────────────────────────────────────────────────────────────

    function tick(nowMs as Number) as Void {
        var elapsed = nowMs - phaseStartMs;

        if (phase == PHASE_TRANSITION) {
            _tickTransition(elapsed, nowMs);
        } else if (phase == PHASE_LOOP && state == STATE_BREATHING) {
            _tickBreathingLoop(elapsed, nowMs);
        } else if (phase == PHASE_HOLD && state == STATE_RECOVERY) {
            _tickRecoveryHold(elapsed, nowMs);
        } else if (phase == PHASE_RETENTION_SEQ && state == STATE_RETENTION) {
            _tickRetentionSequence(elapsed);
        } else if (phase == PHASE_STOPPED_SHRINK && state == STATE_STOPPED) {
            _tickStoppedShrink(elapsed, nowMs);
        }
    }

    // ── Phase tick helpers ────────────────────────────────────────────────────

    function _tickTransition(elapsed as Number, nowMs as Number) as Void {
        // START intro: tiny dot → full circle, then idle at full circle
        if (state == STATE_START) {
            var growDur = START_GROW_MS;
            if (elapsed < growDur) {
                var t = easeInOutCubic(_clamp01(elapsed.toFloat() / growDur.toFloat()));
                scaleCurrent = lerp(scaleFrom, 1.0f, t);
                morphCurrent = 1.0f;
            } else {
                scaleCurrent = 1.0f;
                morphCurrent = 1.0f;
                phase = PHASE_LOOP;
            }
            return;
        }

        var dur = (state == STATE_RECOVERY) ? RECOVERY_TRANS_MS : TRANS_MS;
        var t = easeInOutCubic(_clamp01(elapsed.toFloat() / dur.toFloat()));
        morphCurrent = lerp(morphFrom, morphTo, t);
        scaleCurrent = lerp(scaleFrom, scaleTo, t);

        if ((state == STATE_RECOVERY || state == STATE_STOPPED) && pillFrom > 0.0f) {
            pillT = lerp(pillFrom, 0.0f, t);
        }

        if (elapsed >= dur) {
            morphCurrent = morphTo;
            scaleCurrent = scaleTo;

            if (state == STATE_BREATHING) {
                phase        = PHASE_LOOP;
                phaseStartMs = nowMs;
            } else if (state == STATE_READY) {
                phase        = PHASE_LOOP;
                phaseStartMs = nowMs;
            } else if (state == STATE_RECOVERY) {
                phase        = PHASE_HOLD;
                phaseStartMs = nowMs;
                pillT        = 0.0f;
                lastBeepSec  = -1;
            } else if (state == STATE_RETENTION) {
                phase        = PHASE_RETENTION_SEQ;
                phaseStartMs = nowMs;
            } else if (state == STATE_STOPPED) {
                phase        = PHASE_STOPPED_SHRINK;
                phaseStartMs = nowMs;
                pillT        = 0.0f;
            }
        }
    }

    function _tickBreathingLoop(elapsed as Number, nowMs as Number) as Void {
        if (method == METHOD_478) {
            _tick478Loop(elapsed, nowMs);
            return;
        }

        var cycleMs      = TRANS_MS * 2;
        var maxElapsed   = BREATH_COUNT * cycleMs;

        if (elapsed >= maxElapsed) {
            cycleElapsedMs = 0;
            switchState(STATE_RETENTION, nowMs);
            return;
        }

        var cycleElapsed = elapsed % cycleMs;
        cycleElapsedMs   = cycleElapsed;

        var t = 0.0f;
        if (cycleElapsed < TRANS_MS) {
            t = 1.0f - easeInOutCubic(cycleElapsed.toFloat() / TRANS_MS.toFloat());
        } else {
            t = easeInOutCubic((cycleElapsed - TRANS_MS).toFloat() / TRANS_MS.toFloat());
        }
        scaleCurrent  = lerp(SMALL_SCALE, 1.0f, t);
        morphCurrent  = 1.0f;
    }

    function _tick478Loop(elapsed as Number, nowMs as Number) as Void {
        var cycleMs      = FOUR_SEVEN_EIGHT_CYCLE_MS;
        var cycleElapsed = elapsed % cycleMs;

        // Cycle wrap detection → increment count, maybe auto-stop
        if (cycleElapsed < prevCycleElapsed) {
            cyclesCompleted++;
            if (cyclesCompleted >= FOUR_SEVEN_EIGHT_TARGET_CYCLES) {
                prevCycleElapsed = 0;
                prevSubPhase     = SUBPHASE_INHALE;
                switchState(STATE_STOPPED, nowMs);
                return;
            }
        }
        prevCycleElapsed = cycleElapsed;

        var inhaleEnd = FOUR_SEVEN_EIGHT_INHALE_MS;
        var holdEnd   = FOUR_SEVEN_EIGHT_INHALE_MS + FOUR_SEVEN_EIGHT_HOLD_MS;

        var sp = SUBPHASE_INHALE;
        var scale = SMALL_SCALE;
        var remainingMs = 0;
        if (cycleElapsed < inhaleEnd) {
            sp = SUBPHASE_INHALE;
            var t = easeInOutCubic(cycleElapsed.toFloat() / inhaleEnd.toFloat());
            scale = lerp(SMALL_SCALE, 1.0f, t);
            remainingMs = inhaleEnd - cycleElapsed;
        } else if (cycleElapsed < holdEnd) {
            sp = SUBPHASE_HOLD;
            scale = 1.0f;
            remainingMs = holdEnd - cycleElapsed;
        } else {
            sp = SUBPHASE_EXHALE;
            var t = easeInOutCubic((cycleElapsed - holdEnd).toFloat() / FOUR_SEVEN_EIGHT_EXHALE_MS.toFloat());
            scale = lerp(1.0f, SMALL_SCALE, t);
            remainingMs = cycleMs - cycleElapsed;
        }

        scaleCurrent = scale;
        morphCurrent = 1.0f;
        breathSubPhase = sp;
        subPhaseSecsRemaining = (remainingMs + 999) / 1000;

        if (sp != prevSubPhase) {
            if (sp == SUBPHASE_INHALE) {
                WhmTones.playInhaleCue();
            } else if (sp == SUBPHASE_HOLD) {
                WhmTones.playHoldCue();
            } else {
                WhmTones.playExhaleCue();
            }
            prevSubPhase = sp;
        }
    }

    function _tickRecoveryHold(elapsed as Number, nowMs as Number) as Void {
        morphCurrent = 1.0f;

        if (elapsed < RECOVERY_HOLD_MS) {
            scaleCurrent = 1.0f;
            var remaining = ((RECOVERY_HOLD_MS - elapsed + 999) / 1000);
            if (remaining != lastBeepSec) {
                lastBeepSec = remaining;
                if (remaining == 1) {
                    WhmTones.playCountdownFinal();
                } else {
                    WhmTones.playCountdownTick();
                }
            }
        } else if (elapsed < RECOVERY_HOLD_MS + TRANS_MS) {
            var t = easeInOutCubic((elapsed - RECOVERY_HOLD_MS).toFloat() / TRANS_MS.toFloat());
            scaleCurrent = lerp(1.0f, SMALL_SCALE, t);
        } else if (elapsed < RECOVERY_HOLD_MS + TRANS_MS + RECOVERY_SMALL_WAIT) {
            scaleCurrent = SMALL_SCALE;
        } else {
            scaleCurrent = SMALL_SCALE;
            switchState(STATE_BREATHING, nowMs);
        }
    }

    function _tickRetentionSequence(elapsed as Number) as Void {
        morphCurrent = 1.0f;
        var finishMs = retentionFinishMs;
        var cycleMs  = TRANS_MS * 2;

        if (elapsed < finishMs) {
            var cycleElapsed = (cycleElapsedMs + elapsed) % cycleMs;
            var t = 0.0f;
            if (cycleElapsed < TRANS_MS) {
                t = 1.0f - easeInOutCubic(cycleElapsed.toFloat() / TRANS_MS.toFloat());
            } else {
                t = easeInOutCubic((cycleElapsed - TRANS_MS).toFloat() / TRANS_MS.toFloat());
            }
            scaleCurrent = lerp(SMALL_SCALE, 1.0f, t);

        } else if (elapsed < finishMs + TRANS_MS) {
            var t = easeInOutCubic((elapsed - finishMs).toFloat() / TRANS_MS.toFloat());
            scaleCurrent = lerp(SMALL_SCALE, 1.0f, t);
            pillT        = 0.0f;

        } else if (elapsed < finishMs + TRANS_MS + RETENTION_HOLD_MS) {
            scaleCurrent = 1.0f;
            pillT        = 0.0f;

        } else if (elapsed < finishMs + TRANS_MS + RETENTION_HOLD_MS + TRANS_MS) {
            var t = easeInOutCubic(
                (elapsed - finishMs - TRANS_MS - RETENTION_HOLD_MS).toFloat() / TRANS_MS.toFloat()
            );
            scaleCurrent = lerp(1.0f, SMALL_SCALE, t);
            pillT        = t;

        } else {
            scaleCurrent = SMALL_SCALE;
            pillT        = 1.0f;
            if (phase != PHASE_RETENTION_IDLE) {
                retentionIdleStartMs = phaseStartMs + elapsed;
                phase = PHASE_RETENTION_IDLE;
            }
        }
    }

    function _tickStoppedShrink(elapsed as Number, nowMs as Number) as Void {
        if (stoppedInitRadius < 0.0f) {
            stoppedInitRadius = scaleCurrent;
            stoppedInitMorph  = morphCurrent;
        }

        if (elapsed >= STOPPED_SHRINK_MS) {
            scaleCurrent = INTRO_SCALE;
            morphCurrent = 1.0f;

            var hasResults = (method == METHOD_WHM && retentionTimes.size() > 0)
                          || (method == METHOD_478 && cyclesCompleted > 0);
            if (hasResults) {
                phase         = PHASE_STOPPED_OPTIONS;
                phaseStartMs  = nowMs;
                stoppedOption = 0;
            } else {
                switchState(STATE_START, nowMs);
            }
        } else {
            // Expand to INTRO_SCALE and morph to circle
            var t = easeInOutCubic(elapsed.toFloat() / STOPPED_SHRINK_MS.toFloat());
            scaleCurrent = lerp(stoppedInitRadius, INTRO_SCALE, t);
            morphCurrent = lerp(stoppedInitMorph, 1.0f, t);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _clamp01(v as Float) as Float {
        if (v < 0.0f) { return 0.0f; }
        if (v > 1.0f) { return 1.0f; }
        return v;
    }

    // ── Accessors for View ────────────────────────────────────────────────────

    function getBreathCount() as Number {
        if (state == STATE_BREATHING && phase == PHASE_LOOP) {
            var cycleMs  = TRANS_MS * 2;
            var elapsed  = System.getTimer() - phaseStartMs;
            var done = (elapsed + TRANS_MS) / cycleMs;
            var remaining = BREATH_COUNT - done;
            if (remaining < 0) { remaining = 0; }
            return remaining;
        }
        return 0;
    }

    function getRetentionSeconds() as Number {
        if (state == STATE_RETENTION && phase == PHASE_RETENTION_IDLE
                && retentionIdleStartMs > 0) {
            return (System.getTimer() - retentionIdleStartMs) / 1000;
        }
        // During recovery transition, show the final retention time
        return lastRetentionSecs;
    }

    function getRecoverySecondsRemaining() as Number {
        if (state == STATE_RECOVERY && phase == PHASE_HOLD) {
            var elapsed = System.getTimer() - phaseStartMs;
            if (elapsed < RECOVERY_HOLD_MS) {
                return (RECOVERY_HOLD_MS - elapsed + 999) / 1000;
            }
        }
        return 0;
    }

    function formatSeconds(totalSecs as Number) as String {
        if (totalSecs < 60) {
            return totalSecs.toString() + "s";
        }
        var mins = totalSecs / 60;
        var secs = totalSecs % 60;
        var secStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        return mins.toString() + ":" + secStr + "s";
    }
}
