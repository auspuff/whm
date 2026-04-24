import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class WhmView extends WatchUi.View {

    var mModel as WhmModel;

    // Color constants (ARGB on AMOLED — alpha channel honoured in CIQ 4.x)
    // Solid white at 85% opacity: alpha = round(0.85 * 255) = 0xD9
    const COLOR_WHITE_85  = 0xD9FFFFFF;
    const COLOR_WHITE_50  = 0x80FFFFFF;
    const COLOR_WHITE_FULL = Graphics.COLOR_WHITE;
    const COLOR_BLACK      = Graphics.COLOR_BLACK;
    const COLOR_RED        = 0xFFFF0000;
    const COLOR_BLUE       = 0xFF4488FF;

    // Pill dimensions (fixed — fits up to "9:59")
    const PILL_WIDTH  = 200;
    const PILL_HEIGHT = 74;

    function initialize(model as WhmModel) {
        View.initialize();
        mModel = model;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // Nothing to lay out — we draw everything in onUpdate
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var half = (w < h ? w : h) / 2;
        var r    = (half - 2).toFloat();  // shape radius — full scale reaches screen edge

        var state = mModel.state;
        var phase = mModel.phase;

        // ── Background ─────────────────────────────────────────────────────────
        dc.setColor(COLOR_BLACK, COLOR_BLACK);
        dc.clear();


        // ── Stopped shrink ────────────────────────────────────────────────────
        if (state == STATE_STOPPED && phase == PHASE_STOPPED_SHRINK) {
            _drawShrinkingCircle(dc, cx, cy, r);
            _drawStoppedText(dc, cx, cy, r);
            return;
        }

        // ── Stopped options menu (Save / Delete / Continue) ─────────────────
        if (state == STATE_STOPPED && phase == PHASE_STOPPED_OPTIONS) {
            _drawStoppedOptions(dc, cx, cy, r);
            _drawSessionTime(dc, cx, cy, r);
            return;
        }

        // ── Stopped idle — pageable results ─────────────────────────────────
        if (state == STATE_STOPPED && phase == PHASE_STOPPED_IDLE) {
            if (mModel.method == METHOD_478) {
                _drawGraph(dc, cx, cy, r, mModel.hrSamples, mModel.getHrStats(), "Heart Rate", COLOR_RED);
            } else {
                var page = mModel.resultsPage;
                if (page == 0) {
                    _drawSessionResults(dc, cx, cy, r);
                } else if (page == 1) {
                    _drawGraph(dc, cx, cy, r, mModel.hrSamples, mModel.getHrStats(), "Heart Rate", COLOR_RED);
                } else {
                    _drawGraph(dc, cx, cy, r, mModel.spo2Samples, mModel.getSpo2Stats(), "Pulse Ox", COLOR_BLUE);
                }
                _drawPageDots(dc, cx, cy, r, page);
            }
            _drawSessionTime(dc, cx, cy, r);
            return;
        }

        // ── Pill shape (start/retention idle / transitions with pillT > 0) ──
        var pillT = mModel.pillT;
        var showPill = pillT > 0.0f && (
            state == STATE_RETENTION ||
            state == STATE_RECOVERY  ||
            state == STATE_START     ||
            state == STATE_READY     ||
            state == STATE_BREATHING
        );
        if (showPill) {
            _drawPill(dc, cx, cy, r, pillT);
        } else {
            // ── Normal polygon shape ──────────────────────────────────────────
            _drawPolygon(dc, cx, cy, r);
        }

        // ── Text overlays ─────────────────────────────────────────────────────
        _drawTextOverlay(dc, cx, cy, r);
    }

    // ── Polygon ───────────────────────────────────────────────────────────────

    function _drawPolygon(dc as Graphics.Dc, cx as Number, cy as Number, r as Float) as Void {
        var scale = mModel.scaleCurrent;
        if (scale <= 0.01f) { return; }

        var pts = mModel.computePolygon(cx, cy, r);

        // Outline — draw each edge as a line
        dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var n = NUM_POINTS;
        for (var i = 0; i < n; i++) {
            var j   = (i + 1) % n;
            var p0  = pts[i] as Array<Number>;
            var p1  = pts[j] as Array<Number>;
            dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        }
    }

    // ── Pill shape ────────────────────────────────────────────────────────────

    function _drawPill(
        dc     as Graphics.Dc,
        cx     as Number,
        cy     as Number,
        r      as Float,
        pillT  as Float
    ) as Void {
        var scale       = mModel.scaleCurrent > 0.0f ? mModel.scaleCurrent : 0.0f;
        var circDiam    = (r * 2.0f * scale).toNumber();
        var circR       = (r * scale).toNumber();
        var targetW     = PILL_WIDTH;
        var targetH     = PILL_HEIGHT;
        var targetCorner = PILL_HEIGHT / 2;

        var currentW  = _lerpInt(circDiam, targetW, pillT);
        var currentH  = _lerpInt(circDiam, targetH, pillT);
        var currentR  = _lerpInt(circR,    targetCorner, pillT);

        var x = cx - currentW / 2;
        var y = cy - currentH / 2;

        // Stroke
        dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawRoundedRectangle(x, y, currentW, currentH, currentR);

        // Text inside pill — method label on start, retention timer on
        // retention/recovery, nothing during READY/BREATHING fade-out
        var state = mModel.state;
        var label = null;
        if (state == STATE_START && pillT > 0.3f) {
            label = mModel.getMethodLabel();
        } else if ((state == STATE_RETENTION && pillT > 0.3f)
                || state == STATE_RECOVERY) {
            label = mModel.formatSeconds(mModel.getRetentionSeconds());
        }
        if (label != null) {
            dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_LARGE, label,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ── Shrinking circle (stopped_shrink) ─────────────────────────────────────

    function _drawShrinkingCircle(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        var currentR = (r * mModel.scaleCurrent).toNumber();
        if (currentR < 1) { return; }

        dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawCircle(cx, cy, currentR);
    }

    // ── Session results (stopped_idle) ────────────────────────────────────────

    function _drawSessionResults(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        var times = mModel.retentionTimes;
        if (times.size() == 0) { return; }

        var font       = Graphics.FONT_MEDIUM;
        var lineHeight = dc.getFontHeight(font) + 6;
        var totalH     = times.size() * lineHeight;
        // Center in the space from top of screen to the session time
        var sessionTimeY = (cy + r * 0.58f).toNumber();
        var regionCenter = sessionTimeY / 2;
        var startY     = regionCenter - totalH / 2 + lineHeight / 2;

        dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < times.size(); i++) {
            var label = mModel.formatSeconds((times[i] as Number) / 1000);
            dc.drawText(cx, startY + i * lineHeight, font, label,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

    }

    // ── Stopped options menu (save / delete / continue) ──────────────────────

    function _drawStoppedOptions(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        var labels = ["Save", "Delete", "Continue"];
        var font   = Graphics.FONT_MEDIUM;
        var lineHeight = dc.getFontHeight(font) + 10;
        var totalH     = 3 * lineHeight;

        var footerY = (cy + r * 0.58f).toNumber();
        var regionCenter = footerY / 2;
        var startY = regionCenter - totalH / 2 + lineHeight / 2;

        var active = mModel.stoppedOption;
        for (var i = 0; i < 3; i++) {
            var y = startY + i * lineHeight;
            if (i == active) {
                dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(cx, y, font, labels[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (i == active) {
                var textW = dc.getTextDimensions(labels[i], font)[0];
                var tipX = cx - textW / 2 - 10;
                _drawOptionIndicator(dc, tipX, y);
            }
        }
    }

    // Right-pointing triangle indicator; tip at (tipX, y)
    function _drawOptionIndicator(
        dc as Graphics.Dc, tipX as Number, y as Number
    ) as Void {
        var halfH = 9;
        var w     = 12;
        dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[tipX, y], [tipX - w, y - halfH], [tipX - w, y + halfH]]);
    }

    // ── Text overlays ─────────────────────────────────────────────────────────

    function _drawTextOverlay(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        var state = mModel.state;
        var phase = mModel.phase;

        // Method-select overlay — method label lives inside the pill now,
        // dots sit below it
        if (state == STATE_START && phase != PHASE_TRANSITION) {
            _drawMethodDots(dc, cx, cy, r, mModel.method);
            return;
        }

        // Breath counter during breathing loop
        if (state == STATE_BREATHING && phase == PHASE_LOOP) {
            if (mModel.method == METHOD_478) {
                dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy, Graphics.FONT_LARGE,
                    mModel.subPhaseSecsRemaining.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
            var count = mModel.getBreathCount();
            if (count > 0) {
                dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy, Graphics.FONT_LARGE, count.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            return;
        }

        // Recovery countdown
        if (state == STATE_RECOVERY && phase == PHASE_HOLD) {
            var remaining = mModel.getRecoverySecondsRemaining();
            if (remaining > 0) {
                dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy, Graphics.FONT_LARGE, remaining.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _lerpInt(a as Number, b as Number, t as Float) as Number {
        return (a + (b - a).toFloat() * t).toNumber();
    }

    function _drawStoppedText(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        // Nothing to show while shrinking
    }

    // ── Minimal line graph (shared by HR and SpO2) ──────────────────────────

    function _drawGraph(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float,
        samples as Array, stats as Array, title as String,
        lineColor as Number
    ) as Void {
        var minVal = stats[0] as Number;
        var maxVal = stats[1] as Number;

        // Title
        dc.setColor(COLOR_WHITE_85, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (cy - r * 0.70f).toNumber(), Graphics.FONT_SMALL, title,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (maxVal == 0) {
            dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_SMALL, "No data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Graph bounds — inset to fit round screen, leave room for Y labels
        var labelFont = Graphics.FONT_XTINY;
        var labelW = dc.getTextDimensions(maxVal.toString(), labelFont)[0] + 14;
        var graphL = (cx - r * 0.65f).toNumber() + labelW;
        var graphR = (cx + r * 0.65f).toNumber();
        var graphT = (cy - r * 0.45f).toNumber();
        var graphB = (cy + r * 0.45f).toNumber();
        var graphW = graphR - graphL;
        var graphH = graphB - graphT;

        // Y range with padding
        var yMin = minVal - 5;
        var yMax = maxVal + 5;
        if (yMin < 0) { yMin = 0; }
        var yRange = yMax - yMin;
        if (yRange < 10) { yRange = 10; }

        // Y-axis labels: max near top, min near bottom
        var labelX = graphL - 12;
        var labelInset = (graphH * 0.25f).toNumber();
        dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
        dc.drawText(labelX, graphT + labelInset, labelFont, maxVal.toString(),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(labelX, graphB - labelInset, labelFont, minVal.toString(),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Draw line — downsample to graphW pixels max
        dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var n = samples.size();
        var step = n > graphW ? n / graphW : 1;
        if (step < 1) { step = 1; }
        var prevX = 0;
        var prevY = 0;
        var hadPrev = false;

        for (var i = 0; i < n; i += step) {
            var v = samples[i] as Number;
            if (v == 0) {
                hadPrev = false;
            } else {
                var px = graphL + (i * graphW / n);
                var py = graphB - ((v - yMin) * graphH / yRange);
                if (hadPrev) {
                    dc.drawLine(prevX, prevY, px, py);
                }
                prevX = px;
                prevY = py;
                hadPrev = true;
            }
        }
    }

    // ── Session time (shown on all stopped pages) ─────────────────────────

    function _drawSessionTime(
        dc as Graphics.Dc, cx as Number, cy as Number, r as Float
    ) as Void {
        var secs = mModel.sessionDurationSecs;
        if (secs <= 0) { return; }
        var label = mModel.formatSeconds(secs);
        var y = (cy + r * 0.58f).toNumber();
        dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── Two-dot method indicator (START screen) ─────────────────────────────

    function _drawMethodDots(
        dc as Graphics.Dc, cx as Number, cy as Number,
        r as Float, active as Number
    ) as Void {
        var dotR = 4;
        var spacing = 18;
        var y = (cy + r * 0.40f).toNumber();
        var startX = cx - spacing / 2;

        for (var i = 0; i < 2; i++) {
            var x = startX + i * spacing;
            if (i == active) {
                dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
            }
            dc.fillCircle(x, y, dotR);
        }
    }

    // ── Page indicator dots ─────────────────────────────────────────────────

    function _drawPageDots(
        dc as Graphics.Dc, cx as Number, cy as Number,
        r as Float, activePage as Number
    ) as Void {
        var dotR = 4;
        var spacing = 16;
        var y = (cy + r * 0.82f).toNumber();
        var startX = cx - spacing;

        for (var i = 0; i < 3; i++) {
            var x = startX + i * spacing;
            if (i == activePage) {
                dc.setColor(COLOR_WHITE_FULL, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(COLOR_WHITE_50, Graphics.COLOR_TRANSPARENT);
            }
            dc.fillCircle(x, y, dotR);
        }
    }
}
