# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Wim Hof Method breathing app for the Garmin Fenix 8 43mm, written in Monkey C (Connect IQ SDK). There are also HTML/Canvas prototypes:

- `garmin/prototype/whm-garmin.html` — Garmin watch prototype (reference implementation for the Monkey C app)
- `iphone/prototype/whm-iphone.html` — iPhone prototype
- `iphone/prototype/whm-iphone-circle.html` — iPhone prototype (circle variant)

## Build & Deploy

The SDK lives at `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b`. Set it as a variable for convenience:

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
```

**Build:**
```sh
"$SDK/bin/monkeyc" \
  --output garmin/whm/whm.prg \
  --jungles garmin/whm/monkey.jungle \
  --device fenix843mm \
  --apidb "$SDK/bin/api.db" \
  --apimir "$SDK/bin/api.mir" \
  --import-dbg "$SDK/bin/api.debug.xml" \
  --private-key garmin/developer_key.der
```

**Run in simulator** (start ConnectIQ.app first):
```sh
open "$SDK/bin/ConnectIQ.app"
sleep 5
"$SDK/bin/monkeydo" garmin/whm/whm.prg fenix843mm
```

**Sideload to watch** (connect via USB, accept MTP):
```sh
mtp-sendfile garmin/whm/whm.prg 16777226
```

Folder ID `16777226` is `GARMIN/Apps/` on the watch. Requires `libmtp` (`brew install libmtp`).

Because the manifest declares the `Fit` permission, Fenix 8 classifies the app as an activity profile rather than a CIQ app. After sideloading it won't appear in the Connect IQ app drawer — add it via **Settings → Activities & Apps → Add Activity → Connect IQ → WHM**, then launch from the START activity picker.

## Architecture

The app is in `garmin/whm/source/` with 5 files following a Model-View-Delegate pattern:

- **WhmApp.mc** — App lifecycle. Owns a 50ms repeating `Timer` that calls `model.tick()` then `WatchUi.requestUpdate()`. Also drives the FIT recording lifecycle: creates an `ActivityRecording.Session` on STATE_START → STATE_BREATHING, adds a lap per completed retention round (with a `retention_ms` custom field), and stops/saves with `rounds` and `avg_retention_ms` session fields on the transition to STATE_STOPPED or in `onStop`.
- **WhmModel.mc** — All state, animation math, and timing. Contains the state machine (5 states, 7 phases), polygon precomputation for the morphing shape (60 points), and easing functions. This is the most complex file.
- **WhmView.mc** — Rendering only, no state mutation. Draws the morphing polygon, pill shape (retention timer), and text overlays via `dc.*` calls in `onUpdate()`.
- **WhmDelegate.mc** — Input handling via `BehaviorDelegate`, mapped to Garmin activity conventions: `onSelect` (START/STOP) toggles between start screen, running session, and stopped results; `onBack` (BACK/LAP) advances phases during a session (BREATHING → RETENTION → RECOVERY) and exits the app from the start/stopped screens; `onNextPage`/`onPreviousPage` (DOWN/UP) page through results when stopped; `onTap` is consumed to disable screen-tap input.
- **WhmTones.mc** — Wraps `Attention.playTone()` and `Attention.vibrate()` for audio/haptic cues.

### State Machine

```
START → BREATHING → RETENTION → RECOVERY → (auto loops back to BREATHING)
                                          ↘ STOPPED (via START/STOP button)
```

Each state has sub-phases (e.g., BREATHING has TRANSITION then LOOP; RETENTION has RETENTION_SEQ then RETENTION_IDLE). All timing logic lives in `WhmModel.tick()`.

### Animation

The shape morphs between a rounded triangle (`morphT=0`) and a circle (`morphT=1`) using 60 precomputed polygon points. The triangle radii are computed via ray-edge intersection at startup and stored in `polyTriRadii[]`. Each frame, `computePolygon()` interpolates between triangle and circle radii, applies scale, and writes to a reusable `polygon[]` array.

## Monkey C Gotchas

- Local variables cannot have type annotations (`var x as Float` is invalid — use `var x = 0.0f`)
- Constructors (`initialize()`) cannot have a return type
- Arrays: use `new [N]` not `new Array<Float>[N]`; cast elements on read (`arr[i] as Float`)
- `new WhmModel()` automatically calls `initialize()` — don't call it again
- Scientific notation (`1.0e-10f`) may not work on device — use plain floats
- Timer minimum interval varies by device; 50ms is safe
- `BehaviorDelegate` maps physical buttons to behavior methods (`onSelect`, `onNextPage`, `onBack`) — don't rely on `onKey()` alone for touch+button devices
- `onBack()` must return `false` when not handling (to let system exit the app) — always-true traps the user
