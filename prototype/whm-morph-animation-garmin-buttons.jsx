import { useState, useEffect, useRef, useCallback } from "react";

// Load rounded font
const fontLink = document.createElement("link");
fontLink.href = "https://fonts.googleapis.com/css2?family=Nunito:wght@300;400;500&display=swap";
fontLink.rel = "stylesheet";
document.head.appendChild(fontLink);

const ROUND_FONT = "'Nunito', sans-serif";

function lerp(a, b, t) {
  return a + (b - a) * t;
}

const TRI_VERTS = [
  { x: -0.7, y: -1 },
  { x: -0.7, y: 1 },
  { x: 1, y: 0 },
];

function rayEdgeDist(dx, dy, ax, ay, bx, by) {
  const ex = bx - ax;
  const ey = by - ay;
  const denom = dx * ey - dy * ex;
  if (Math.abs(denom) < 1e-10) return Infinity;
  const t = (ax * ey - ay * ex) / denom;
  const u = (ax * dy - ay * dx) / denom;
  if (t > 0 && u >= 0 && u <= 1) return t;
  return Infinity;
}

function getTriangleRadius(angle, r) {
  const dx = Math.cos(angle);
  const dy = Math.sin(angle);
  let minDist = Infinity;
  for (let i = 0; i < 3; i++) {
    const a = TRI_VERTS[i];
    const b = TRI_VERTS[(i + 1) % 3];
    const d = rayEdgeDist(dx, dy, a.x * r, a.y * r, b.x * r, b.y * r);
    if (d < minDist) minDist = d;
  }
  return minDist;
}

const VERT_ANGLES = TRI_VERTS.map((v) => Math.atan2(v.y, v.x));

// Precompute smoothed triangle radii by applying a moving average to round corners
const SMOOTH_WINDOW = 2; // number of neighbors on each side to average

function precomputeSmoothedRadii(angles) {
  // First get raw triangle radii at unit r
  const raw = angles.map((a) => getTriangleRadius(a, 1));
  // Apply moving average (wrapping)
  const n = raw.length;
  const smoothed = new Array(n);
  for (let i = 0; i < n; i++) {
    let sum = 0;
    let count = 0;
    for (let j = -SMOOTH_WINDOW; j <= SMOOTH_WINDOW; j++) {
      const idx = (i + j + n) % n;
      sum += raw[idx];
      count++;
    }
    smoothed[i] = sum / count;
  }
  return smoothed;
}

function buildAngles(numPoints) {
  const sorted = [...VERT_ANGLES].sort((a, b) => a - b);
  const arcs = [];
  for (let i = 0; i < sorted.length; i++) {
    const from = sorted[i];
    const to = sorted[(i + 1) % sorted.length];
    const span = to > from ? to - from : to - from + 2 * Math.PI;
    arcs.push({ from, span });
  }
  const remaining = numPoints - 3;
  const angles = [];
  for (let a = 0; a < arcs.length; a++) {
    const arc = arcs[a];
    angles.push(arc.from);
    const count = Math.round(remaining * (arc.span / (2 * Math.PI)));
    for (let i = 1; i <= count; i++) {
      let ang = arc.from + (i / (count + 1)) * arc.span;
      if (ang > Math.PI) ang -= 2 * Math.PI;
      angles.push(ang);
    }
  }
  angles.sort((a, b) => a - b);
  return angles;
}

const NUM_POINTS = 120;
const PREBUILT_ANGLES = buildAngles(NUM_POINTS);
const SMOOTHED_RADII = precomputeSmoothedRadii(PREBUILT_ANGLES);

function getPoints(cx, cy, r, morphT, scale) {
  // scale: 0 = nothing, 0.18 = small (breathing min), 1 = big
  // Clamp to 0 minimum
  const scaleFactor = Math.max(0, scale);
  const points = [];
  for (let i = 0; i < PREBUILT_ANGLES.length; i++) {
    const angle = PREBUILT_ANGLES[i];
    const circR = r;
    const triR = SMOOTHED_RADII[i] * r;
    const dist = lerp(triR, circR, morphT) * scaleFactor;
    points.push({
      x: cx + dist * Math.cos(angle),
      y: cy + dist * Math.sin(angle),
    });
  }
  return points;
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

const TRANS_MS = 2000;
const SMALL_SCALE = 0.18; // the "small" circle size in breathing

export default function MorphAnimation() {
  const canvasRef = useRef(null);
  const animRef = useRef(null);

  const stateRef = useRef("start");
  const phaseRef = useRef("transition");
  const phaseStartRef = useRef(performance.now());

  const morphRef = useRef(0);
  const scaleRef = useRef(0);

  const morphFromRef = useRef(0);
  const scaleFromRef = useRef(0);
  const morphToRef = useRef(0);
  const scaleToRef = useRef(0.3);

  const [activeState, setActiveState] = useState("start");
  const retentionFinishMsRef = useRef(0);
  const breathingCycleElapsedRef = useRef(0);
  const retentionIdleStartRef = useRef(0);
  const pillTRef = useRef(0); // 0=circle, 1=pill shape
  const pillFromRef = useRef(0); // snapshot of pillT at state switch
  const retentionTextRef = useRef(""); // current timer text for measuring
  const animatedPillWidthRef = useRef(0); // smoothly animated pill width
  const textAlphaRef = useRef(0); // smoothly animated text opacity
  const currentTextRef = useRef(""); // text currently being displayed
  const retentionTimesRef = useRef([]); // array of retention durations in ms
  const stoppedAlphaRef = useRef(0); // fade-in for stopped results
  const stoppedStartRef = useRef(0); // when stopped phase began
  const stoppedRadiusRef = useRef(-1); // -1 = not in stopped shrink

  const switchState = useCallback((newState) => {
    const now = performance.now();
    
    // Record retention time if leaving retention_idle
    if (stateRef.current === "retention" && phaseRef.current === "retention_idle" && retentionIdleStartRef.current > 0) {
      const duration = now - retentionIdleStartRef.current;
      retentionTimesRef.current = [...retentionTimesRef.current, duration];
    }
    
    morphFromRef.current = morphRef.current;
    scaleFromRef.current = scaleRef.current;
    stoppedRadiusRef.current = -1;
    
    const pillFrom = pillTRef.current;

    stateRef.current = newState;
    phaseRef.current = "transition";
    phaseStartRef.current = now;
    setActiveState(newState);

    switch (newState) {
      case "start":
        morphToRef.current = 0;
        scaleToRef.current = 0.3;
        morphFromRef.current = 0;
        scaleFromRef.current = 0;
        pillTRef.current = 0;
        animatedPillWidthRef.current = 0;
        retentionTimesRef.current = []; // reset session
        break;
      case "breathing":
        morphToRef.current = 1;
        scaleToRef.current = 1;
        pillTRef.current = 0;
        animatedPillWidthRef.current = 0;
        break;
      case "retention": {
        morphToRef.current = 1;
        // Continue breathing until circle reaches small.
        // Breathing cycle: 0..TRANS_MS = big->small, TRANS_MS..cycleMs = small->big
        // "small" is at cycleElapsed = TRANS_MS
        const cyclePos = breathingCycleElapsedRef.current || 0;
        let remainToSmall;
        if (cyclePos <= TRANS_MS) {
          // Going big->small, just finish this half
          remainToSmall = TRANS_MS - cyclePos;
        } else {
          // Going small->big, finish to big then big->small
          remainToSmall = (TRANS_MS * 2 - cyclePos) + TRANS_MS;
        }
        retentionFinishMsRef.current = remainToSmall;
        phaseRef.current = "retention_sequence";
        break;
      }
      case "recovery":
        morphToRef.current = 1;
        scaleToRef.current = 1;
        pillFromRef.current = pillFrom;
        break;
      case "stopped": {
        morphToRef.current = 1;
        morphRef.current = 1;
        stoppedAlphaRef.current = 0;
        pillTRef.current = 0;
        animatedPillWidthRef.current = 0;
        // Go straight to shrink phase
        phaseRef.current = "stopped_shrink";
        break;
      }
    }
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;

    function resize() {
      const rect = canvas.getBoundingClientRect();
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener("resize", resize);

    function draw(timestamp) {
      const rect = canvas.getBoundingClientRect();
      const w = rect.width;
      const h = rect.height;
      const cx = w / 2;
      const cy = h / 2;
      const r = Math.min(w, h) * 0.3;

      const elapsed = timestamp - phaseStartRef.current;
      const state = stateRef.current;
      const phase = phaseRef.current;

      if (phase === "transition") {
        const t = easeInOutCubic(Math.min(1, elapsed / TRANS_MS));
        morphRef.current = lerp(morphFromRef.current, morphToRef.current, t);
        scaleRef.current = lerp(scaleFromRef.current, scaleToRef.current, t);
        
        // Animate pill back to circle during recovery/stopped transition
        if ((state === "recovery" || state === "stopped") && pillFromRef.current > 0) {
          pillTRef.current = lerp(pillFromRef.current, 0, t);
        }

        if (elapsed >= TRANS_MS) {
          morphRef.current = morphToRef.current;
          scaleRef.current = scaleToRef.current;

          if (state === "breathing") {
            phaseRef.current = "loop";
            phaseStartRef.current = timestamp;
          } else if (state === "recovery") {
            phaseRef.current = "hold";
            phaseStartRef.current = timestamp;
            pillTRef.current = 0;
            animatedPillWidthRef.current = 0;
          } else if (state === "retention") {
            phaseRef.current = "retention_sequence";
            phaseStartRef.current = timestamp;
          } else if (state === "stopped") {
            phaseRef.current = "stopped_shrink";
            phaseStartRef.current = timestamp;
            pillTRef.current = 0;
            animatedPillWidthRef.current = 0;
          } else {
            phaseRef.current = "idle";
          }
        }
      } else if (phase === "loop" && state === "breathing") {
        const cycleMs = TRANS_MS * 2;
        const totalBreaths = 3;
        const maxElapsed = totalBreaths * cycleMs;
        
        // After 3 breaths, switch to retention
        if (elapsed >= maxElapsed) {
          breathingCycleElapsedRef.current = 0; // at the start of a cycle = big
          stateRef.current = "retention";
          phaseRef.current = "retention_sequence";
          phaseStartRef.current = timestamp;
          retentionFinishMsRef.current = TRANS_MS; // finish big->small
          setActiveState("retention");
        } else {
          const cycleElapsed = elapsed % cycleMs;
          breathingCycleElapsedRef.current = cycleElapsed;
          let t;
          if (cycleElapsed < TRANS_MS) {
            t = 1 - easeInOutCubic(cycleElapsed / TRANS_MS);
          } else {
            t = easeInOutCubic((cycleElapsed - TRANS_MS) / TRANS_MS);
          }
          scaleRef.current = lerp(SMALL_SCALE, 1, t);
          morphRef.current = 1;
        }
      } else if (phase === "hold" && state === "recovery") {
        if (elapsed < 3000) {
          scaleRef.current = 1;
        } else if (elapsed < 3000 + TRANS_MS) {
          const t = easeInOutCubic((elapsed - 3000) / TRANS_MS);
          scaleRef.current = lerp(1, SMALL_SCALE, t);
        } else if (elapsed < 3000 + TRANS_MS + 3000) {
          scaleRef.current = SMALL_SCALE;
        } else {
          scaleRef.current = SMALL_SCALE;
          // Go to breathing state, start loop from small (= TRANS_MS into cycle)
          stateRef.current = "breathing";
          phaseRef.current = "loop";
          phaseStartRef.current = timestamp - TRANS_MS; // offset so cycle starts at small->big
          breathingCycleElapsedRef.current = TRANS_MS;
          setActiveState("breathing");
        }
        morphRef.current = 1;
      } else if (phase === "retention_sequence" && state === "retention") {
        const finishMs = retentionFinishMsRef.current;
        const cycleMs = TRANS_MS * 2;
        const startCyclePos = breathingCycleElapsedRef.current;
        
        if (elapsed < finishMs) {
          // Continue breathing animation until small is reached
          const cycleElapsed = (startCyclePos + elapsed) % cycleMs;
          let t;
          if (cycleElapsed < TRANS_MS) {
            t = 1 - easeInOutCubic(cycleElapsed / TRANS_MS);
          } else {
            t = easeInOutCubic((cycleElapsed - TRANS_MS) / TRANS_MS);
          }
          scaleRef.current = lerp(SMALL_SCALE, 1, t);
        } else if (elapsed < finishMs + TRANS_MS) {
          // small -> big at breathing speed
          const t = easeInOutCubic((elapsed - finishMs) / TRANS_MS);
          scaleRef.current = lerp(SMALL_SCALE, 1, t);
        } else if (elapsed < finishMs + TRANS_MS + 1000) {
          // hold big for 1s
          scaleRef.current = 1;
        } else if (elapsed < finishMs + TRANS_MS + 1000 + TRANS_MS) {
          // big circle -> pill shape at breathing speed
          const t = easeInOutCubic((elapsed - finishMs - TRANS_MS - 1000) / TRANS_MS);
          scaleRef.current = lerp(1, SMALL_SCALE, t);
          pillTRef.current = t;
        } else {
          scaleRef.current = SMALL_SCALE;
          pillTRef.current = 1;
          if (phaseRef.current !== "retention_idle") {
            retentionIdleStartRef.current = timestamp;
          }
          phaseRef.current = "retention_idle";
        }
        morphRef.current = 1;
      }
      
      // Stopped shrink phase - compute radius
      if (phase === "stopped_shrink" && state === "stopped") {
        if (stoppedRadiusRef.current < 0) {
          stoppedRadiusRef.current = r * Math.max(0, scaleFromRef.current);
        }
        
        const initR = stoppedRadiusRef.current;
        const shrinkDuration = 1000;
        const t = easeInOutCubic(Math.min(1, elapsed / shrinkDuration));
        const currentR = initR * (1 - t);
        
        if (elapsed >= shrinkDuration) {
          stoppedRadiusRef.current = 0;
          if (retentionTimesRef.current.length > 0) {
            phaseRef.current = "stopped_idle";
            phaseStartRef.current = timestamp;
          } else {
            morphFromRef.current = 0;
            scaleFromRef.current = 0;
            morphToRef.current = 0;
            scaleToRef.current = 0.3;
            stateRef.current = "start";
            phaseRef.current = "transition";
            phaseStartRef.current = timestamp;
            setActiveState("start");
          }
        }
      }

      ctx.clearRect(0, 0, w, h);

      // Background circle
      const bgRadius = r * 1.15;
      ctx.beginPath();
      ctx.arc(cx, cy, bgRadius, 0, Math.PI * 2);
      ctx.fillStyle = "#141414";
      ctx.fill();

      // Draw shrinking circle during stopped_shrink (after background)
      if (phase === "stopped_shrink" && state === "stopped") {
        const initR = stoppedRadiusRef.current;
        const shrinkDuration = 1000;
        const t = easeInOutCubic(Math.min(1, elapsed / shrinkDuration));
        const currentR = initR * (1 - t);
        if (currentR > 0.5) {
          ctx.save();
          ctx.shadowColor = "rgba(255, 255, 255, 0.4)";
          ctx.shadowBlur = 16;
          ctx.beginPath();
          ctx.arc(cx, cy, currentR, 0, Math.PI * 2);
          ctx.strokeStyle = "#ffffff";
          ctx.lineWidth = 2.5;
          ctx.stroke();
          ctx.restore();
          
          ctx.beginPath();
          ctx.arc(cx, cy, currentR, 0, Math.PI * 2);
          ctx.fillStyle = "rgba(255, 255, 255, 0.04)";
          ctx.fill();
        }
      }

      const pillT = pillTRef.current;
      const fontSize = r * 0.22;
      
      const isStopped = state === "stopped" && (phase === "stopped_shrink" || phase === "stopped_idle");
      
      // Compute retention timer text if needed
      let retentionTimerText = "";
      if (state === "retention" && (phase === "retention_idle" || (phase === "retention_sequence" && pillT > 0))) {
        const holdStart = retentionIdleStartRef.current;
        const holdElapsed = phase === "retention_idle" ? timestamp - holdStart : 0;
        const totalSecs = Math.floor(holdElapsed / 1000);
        if (totalSecs < 60) {
          retentionTimerText = `${totalSecs}s`;
        } else {
          const mins = Math.floor(totalSecs / 60);
          const secs = totalSecs % 60;
          retentionTimerText = `${mins}:${secs.toString().padStart(2, "0")}`;
        }
        retentionTextRef.current = retentionTimerText || "0s";
      }

      if (!isStopped && pillT > 0 && (state === "retention" || state === "recovery" || state === "stopped")) {
        // Measure text to get target pill width
        ctx.save();
        ctx.font = `600 ${fontSize}px Nunito, sans-serif`;
        const textToMeasure = retentionTextRef.current || "0";
        const textWidth = ctx.measureText(textToMeasure).width;
        ctx.restore();

        const paddingX = fontSize * 0.8;
        const smallCircleDiameter = r * SMALL_SCALE * 2; // matches breathing small state
        const pillHeight = smallCircleDiameter;
        const paddingY = (pillHeight - fontSize) / 2;
        const targetPillWidth = textWidth + paddingX * 2;
        const pillRadius = pillHeight / 2;

        // Smoothly animate pill width
        if (animatedPillWidthRef.current === 0) {
          animatedPillWidthRef.current = targetPillWidth;
        } else {
          const speed = 0.08;
          animatedPillWidthRef.current = lerp(animatedPillWidthRef.current, targetPillWidth, speed);
        }
        const pillWidth = animatedPillWidthRef.current;

        // Circle params at current scale
        const circleRadius = r * Math.max(0, scaleRef.current);

        // Interpolate between circle and pill
        const currentW = lerp(circleRadius * 2, pillWidth, pillT);
        const currentH = lerp(circleRadius * 2, pillHeight, pillT);
        const currentRadius = lerp(circleRadius, pillRadius, pillT);

        const x = cx - currentW / 2;
        const y = cy - currentH / 2;

        // Draw rounded rect
        const glowIntensity = 1;
        ctx.save();
        ctx.shadowColor = `rgba(255, 255, 255, ${0.25 + glowIntensity * 0.25})`;
        ctx.shadowBlur = 14 + glowIntensity * 10;
        ctx.beginPath();
        ctx.roundRect(x, y, currentW, currentH, currentRadius);
        ctx.strokeStyle = "#ffffff";
        ctx.lineWidth = 2.5;
        ctx.stroke();
        ctx.restore();

        ctx.beginPath();
        ctx.roundRect(x, y, currentW, currentH, currentRadius);
        ctx.fillStyle = `rgba(255, 255, 255, 0.04)`;
        ctx.fill();

        // Draw text inside pill (fade with pillT)
        if (pillT > 0.3) {
          const textAlpha = Math.min(1, (pillT - 0.3) / 0.7) * 0.85;
          ctx.save();
          ctx.font = `600 ${fontSize}px Nunito, sans-serif`;
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillStyle = `rgba(255, 255, 255, ${textAlpha})`;
          ctx.fillText(retentionTextRef.current, cx - 1, cy + 4);
          ctx.restore();
        }
      } else if (!isStopped) {
        // Normal point-based shape drawing
        const morphed = getPoints(cx, cy, r, morphRef.current, scaleRef.current);

        // Fade opacity when shape is very small
        const shapeOpacity = Math.min(1, scaleRef.current / 0.15);
        const glowIntensity = morphRef.current;
        ctx.save();
        ctx.globalAlpha = Math.max(0, shapeOpacity);
        ctx.shadowColor = `rgba(255, 255, 255, ${0.25 + glowIntensity * 0.25})`;
        ctx.shadowBlur = 14 + glowIntensity * 10;

        ctx.beginPath();
        ctx.moveTo(morphed[0].x, morphed[0].y);
        for (let i = 1; i < morphed.length; i++) {
          ctx.lineTo(morphed[i].x, morphed[i].y);
        }
        ctx.closePath();

        ctx.strokeStyle = "#ffffff";
        ctx.lineWidth = 2.5;
        ctx.lineJoin = "miter";
        ctx.miterLimit = 20;
        ctx.lineCap = "round";
        ctx.stroke();
        ctx.restore();

        ctx.beginPath();
        ctx.moveTo(morphed[0].x, morphed[0].y);
        for (let i = 1; i < morphed.length; i++) {
          ctx.lineTo(morphed[i].x, morphed[i].y);
        }
        ctx.closePath();
        ctx.fillStyle = `rgba(255, 255, 255, ${0.02 + glowIntensity * 0.02})`;
        ctx.fill();
      }

      // Unified text system with smooth fade
      let targetText = "";
      let targetAlpha = 0;

      // During transitions, force alpha to 0 for clean fade-in
      if (phase === "transition") {
        textAlphaRef.current = lerp(textAlphaRef.current, 0, 0.15);
      }

      // Recovery countdown
      if (state === "recovery" && phase === "hold" && elapsed < 3000) {
        const remaining = Math.ceil((3000 - elapsed) / 1000);
        targetText = `${remaining}`;
        targetAlpha = 0.85;
      }

      // Breathing count
      if (state === "breathing" && phase === "loop") {
        const cycleMs = TRANS_MS * 2;
        const breathCount = Math.floor((elapsed + TRANS_MS) / cycleMs);
        if (breathCount > 0) {
          targetText = `${breathCount}`;
          targetAlpha = 0.85;
        }
      }

      // Stopped results - build text for unified fade system
      if (state === "stopped" && phase === "stopped_idle") {
        const times = retentionTimesRef.current;
        if (times.length > 0) {
          const lines = times.map(t => {
            const totalSecs = Math.floor(t / 1000);
            if (totalSecs < 60) return `${totalSecs}s`;
            const mins = Math.floor(totalSecs / 60);
            const secs = totalSecs % 60;
            return `${mins}:${secs.toString().padStart(2, "0")}`;
          });
          targetText = lines.join("\n");
          targetAlpha = 0.85;
        }
      }

      // Update text content (change immediately when new text is ready)
      if (targetText && targetAlpha > 0) {
        currentTextRef.current = targetText;
      }

      // Smooth fade (faster fade-in, slower fade-out)
      const fadeSpeed = targetAlpha > textAlphaRef.current ? 0.15 : 0.12;
      textAlphaRef.current = lerp(textAlphaRef.current, targetAlpha, fadeSpeed);

      // Draw text if visible
      if (textAlphaRef.current > 0.01 && currentTextRef.current) {
        ctx.save();
        ctx.font = `600 ${fontSize}px Nunito, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillStyle = `rgba(255, 255, 255, ${textAlphaRef.current})`;
        
        const lines = currentTextRef.current.split("\n");
        if (lines.length > 1) {
          const lineHeight = fontSize * 1.6;
          const totalHeight = lines.length * lineHeight;
          const startY = cy - totalHeight / 2 + lineHeight / 2;
          for (let i = 0; i < lines.length; i++) {
            ctx.fillText(lines[i], cx - 1, startY + i * lineHeight);
          }
        } else {
          ctx.fillText(currentTextRef.current, cx - 1, cy + 4);
        }
        
        ctx.restore();
      }

      animRef.current = requestAnimationFrame(draw);
    }

    animRef.current = requestAnimationFrame(draw);

    return () => {
      window.removeEventListener("resize", resize);
      if (animRef.current) cancelAnimationFrame(animRef.current);
    };
  }, []);

  const btnStyle = (name) => ({
    padding: "10px 20px",
    border: `1.5px solid ${activeState === name ? "#fff" : "rgba(255,255,255,0.25)"}`,
    borderRadius: "999px",
    background: activeState === name ? "rgba(255,255,255,0.12)" : "transparent",
    color: activeState === name ? "#fff" : "rgba(255,255,255,0.5)",
    cursor: "pointer",
    fontSize: "13px",
    fontFamily: "Nunito, sans-serif",
    fontWeight: 500,
    letterSpacing: "0.5px",
    textTransform: "uppercase",
    transition: "all 0.3s ease",
    outline: "none",
  });

  const watchBtn = {
    position: "absolute",
    padding: "4px 10px",
    border: "1px solid rgba(255,255,255,0.15)",
    borderRadius: "4px",
    background: "rgba(255,255,255,0.04)",
    color: "rgba(255,255,255,0.3)",
    cursor: "default",
    fontSize: "9px",
    fontFamily: "Nunito, sans-serif",
    fontWeight: 600,
    letterSpacing: "0.8px",
    textTransform: "uppercase",
    outline: "none",
    whiteSpace: "nowrap",
  };

  return (
    <div
      style={{
        width: "100vw",
        height: "100vh",
        background: "#0a0a0a",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div style={{ position: "relative", width: "420px", height: "420px" }}>
        <canvas
          ref={canvasRef}
          style={{ width: "420px", height: "420px", cursor: "pointer" }}
          onClick={() => {
            if (activeState === "start") switchState("breathing");
            else if (activeState === "breathing") switchState("retention");
            else if (activeState === "retention") switchState("recovery");
            else if (activeState === "stopped") switchState("start");
          }}
        />
        <div style={{ ...watchBtn, left: "-62px", top: "68px" }}>LIGHT</div>
        <div style={{ ...watchBtn, left: "-46px", top: "50%", transform: "translateY(-50%)" }}>UP</div>
        <div style={{ ...watchBtn, left: "-62px", bottom: "68px", cursor: "pointer" }}
          onClick={() => {
            if (activeState === "breathing") {
              switchState("retention");
            } else if (activeState === "retention") {
              switchState("recovery");
            }
          }}
        >DOWN</div>
        <div style={{ ...watchBtn, right: "-88px", top: "68px", cursor: "pointer" }}
          onClick={() => {
            if (activeState === "start") {
              switchState("breathing");
            } else {
              switchState("stopped");
            }
          }}
        >START/STOP</div>
        <div style={{ ...watchBtn, right: "-60px", bottom: "68px" }}>BACK</div>
      </div>
      <div style={{ display: "flex", gap: "12px", marginTop: "24px" }}>
        <button style={btnStyle("start")} onClick={() => switchState("start")}>
          Start
        </button>
        <button style={btnStyle("breathing")} onClick={() => switchState("breathing")}>
          Breathing
        </button>
        <button style={btnStyle("retention")} onClick={() => switchState("retention")}>
          Retention
        </button>
        <button style={btnStyle("recovery")} onClick={() => switchState("recovery")}>
          Recovery
        </button>
        <button style={btnStyle("stopped")} onClick={() => switchState("stopped")}>
          Stopped
        </button>
      </div>
    </div>
  );
}
