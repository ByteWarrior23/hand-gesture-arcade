# Hand Gesture Arcade

Webcam hand control for two games. MediaPipe HandLandmarker runs in the browser
and maps hand position and swipes to game input. Everything runs locally on
`127.0.0.1`; camera frames never leave the machine.

Two games, two control models:

| Game | Where it runs | Input path |
|---|---|---|
| Subway Surfers | Android app in BlueStacks 5 | Discrete swipe commands via ADB |
| Level Devil | Browser platformer | Continuous position-hold via keyboard |

Both games can also be played with the keyboard directly.

## Subway Surfers

Real game in BlueStacks. A hand swipe is one discrete command: left, right,
jump, or roll. Each swipe fires once, then the game idles until the next swipe.

Numerical behavior (browser-side MediaPipe HandLandmarker, GPU delegate,
640x480 input, 30 FPS video):

- Swipe tracker window: 450 ms, minimum displacement 0.05, velocity gate 0.2,
  280 ms cooldown, 2-frame confirm, EMA smoothing alpha 0.7.
- End-to-end latency: detection (~33 ms) + POST (~5 ms) + ADB swipe (90 ms)
  gives a command latency of roughly 100-140 ms.
- Server throttle: 260 ms per action.
- Hand acceptance: best-scoring hand, `hand_score >= 0.5`.

### Controls

| Gesture | Command | Key equivalent |
|---|---|---|
| Swipe hand left | Swipe left | Left arrow |
| Swipe hand right | Swipe right | Right arrow |
| Swipe hand up | Jump | Up arrow |
| Swipe hand down | Roll | Down arrow |

## Level Devil

Browser platformer. Hand position maps to held keys: hold the hand at the far
left or right edge to keep moving, raise it to jump. Position is continuous,
so the key stays held while the hand stays in the zone.

Numerical behavior:

- Left zone: engage `x < 0.24`, release `x > 0.45` (mirrored frame x).
- Right zone: engage `x > 0.76`, release `x < 0.55`.
- Jump zone: `y < 0.42`; while a direction is held, jump engages at `y < 0.55`
  (release hysteresis +0.08) so right+up and left+up hold both keys.
- Rest zone: hand low (`y > 0.70`) releases every key.
- Index-finger double tap (two curls within 500 ms) sends a click (Space).
- Latency: one camera frame (~33 ms) plus a local POST (~5 ms).

### Controls

| Gesture | Action | Key |
|---|---|---|
| Hand at far left | Hold left | Left arrow |
| Hand at far right | Hold right | Right arrow |
| Hand raised | Hold jump | Space |
| Hand raised + side | Hold direction + jump | Arrows + Space |
| Index-finger double tap | Click | Space |
| Hand low or center | Stop (release all) | - |

## Architecture

```
hand-gesture-arcade/
  src/       Python backend - web server, input bridge, BlueStacks setup
  web/       Frontend - hub, shared JS, game pages, MediaPipe WASM vendor files
  models/    MediaPipe hand landmarker model (hand_landmarker.task)
  scripts/   Setup and start scripts
  tools/     ADB platform-tools (large binaries gitignored)
  tests/     Route and API smoke tests
```

Data flow:

1. The browser loads `hand_landmarker.task` and the MediaPipe WASM bundle from
   the local server.
2. Each camera frame is classified in the browser by `HandLandmarker`
   (`runningMode: VIDEO`).
3. The bridge converts hand state to game input and posts only the final
   action to the server.
4. The server dispatches it: ADB swipe for Subway Surfers, key hold/tap for
   Level Devil.

## HTTP API

| Endpoint | Method | Body | Effect |
|---|---|---|---|
| `/health` | GET | - | `{"ok": true}` |
| `/api/status` | GET | - | BlueStacks/ADB state |
| `/api/action` | POST | `{game, action}` | One command (swipe, jump, ...) |
| `/api/key` | POST | `{game, key, state}` | Hold/release/tap a key |
| `/api/launch` | POST | `{game}` | Launch the game |
| `/api/prepare` | POST | `{game}` | Full setup: BlueStacks + ADB + game |
| `/api/connect` | POST | - | Connect ADB |
| `/api/bluestacks/start` | POST | - | Start BlueStacks |
| `/api/setup` | POST | `{games}` | Install BlueStacks, ADB, APKs |

## Setup

Requirements: Windows, Python 3.11+.

```
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

Install BlueStacks 5 (one time): double-click `scripts/install_bluestacks.bat`,
then in BlueStacks enable Settings > Advanced > Android Debug Bridge and install
Subway Surfers from the Play Store (or let the arcade sideload it on first run).

Start:

```
scripts\start_arcade.bat
```

Open http://127.0.0.1:8123 and pick a game.

Tests:

```
python tests\test_server_routes.py
```

## Notes

- `models/hand_landmarker.task` is the standard MediaPipe float16 model
  (~7.8 MB). It is committed so the arcade runs out of the box.
- `tools/apks/` and the BlueStacks installer are downloaded at runtime and
  gitignored; `tools/platform-tools/` (ADB) is committed.
- Subway Surfers APK sideloading retries across APK mirror URLs in
  `src/arcade_setup.py`.
