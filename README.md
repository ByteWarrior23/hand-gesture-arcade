# Hand Gesture Arcade

Webcam hand control for two games. MediaPipe HandLandmarker runs in the browser
and maps hand position to game input. Everything runs locally on
`127.0.0.1`; camera frames never leave the machine.

Two games, two control models:

| Game | Where it runs | Input path |
|---|---|---|
| Subway Surfers | Browser game on Poki | Index-finger swipes → arrow keys |
| Level Devil | Browser platformer | Hold hand zones → keyboard |

Both games can also be played with the keyboard directly.

## Subway Surfers

Web version of the game on Poki, controlled like the classic MediaPipe demo:
track the index fingertip and flick it — each flick fires one arrow key
(pydirectinput press, ~10 ms). No emulator, no ADB, so command latency is a
single camera frame plus the local POST (roughly 40-50 ms).

Numerical behavior (browser-side MediaPipe HandLandmarker, GPU delegate,
640x480 input, 30 FPS video):

- Swipe source: index fingertip (landmark 8), mirrored x.
- A flick only counts when it starts inside the neutral center zone
  (`x` and `y` in `0.30..0.70`), moves at least `0.14` from the start within
  `400 ms`, and is dominant on one axis (1.3x). This is what stops lowering
  your hand after an up flick from triggering roll.
- After each flick the hand must return to center to unlock the next one.
- Cooldown: 250 ms between flicks.
- Command latency: detection (~33 ms) + POST (~5 ms) + key press (~10 ms).
- Hand acceptance: best-scoring hand, `hand_score >= 0.5`.

### Controls

| Gesture | Command | Key equivalent |
|---|---|---|
| Flick finger left | Lane left | Left arrow |
| Flick finger right | Lane right | Right arrow |
| Flick finger up | Jump | Up arrow |
| Flick finger down | Roll | Down arrow |
| Hand in center | Reset between flicks | - |

## Level Devil

Browser platformer. Hand position maps to held keys, split into side zones: the
far left/right edges of the frame run that direction, the center is neutral.
Within an active side, the hand's height chooses the mode. Position is
continuous, so the key stays held while the hand stays in the zone.

Numerical behavior:

- Left zone: engage `x < 0.24`, release `x > 0.45` (mirrored frame x).
- Right zone: engage `x > 0.76`, release `x < 0.55`.
- Within a side, hand at natural height = direction only; raise the hand clearly
  above shoulder/head level (`y < 0.42`, release hysteresis to `y > 0.50`) =
  direction + jump. While raised on a side, Space is tapped every 280 ms so the
  character keeps jumping while running (jump + right + jump + right).
- In the center, a raised hand is a plain jump hold (Space), and a low hand is
  neutral (no keys held).
- Index-finger double tap (two curls within 500 ms) sends a click (Space).
- Latency: one camera frame (~33 ms) plus a local POST (~5 ms).

### Controls

| Gesture | Action | Key |
|---|---|---|
| Hand at natural height on left/right side | Hold that direction | Left/Right arrow |
| Hand raised above shoulder level on a side | Run + keep jumping | Arrows + Space |
| Hand raised in the center | Jump in place (hold) | Space |
| Hand low in the center | Stop (release all) | - |
| Index-finger double tap | Click | Space |

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
