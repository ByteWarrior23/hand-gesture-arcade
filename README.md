# Hand Gesture Arcade

Webcam hand control for two games. MediaPipe HandLandmarker runs in the browser
and maps hand position to game input. Everything runs locally on
`127.0.0.1`; camera frames never leave the machine.

Two games, one control model:

| Game | Where it runs | Input path |
|---|---|---|
| Subway Surfers | Android app in BlueStacks 5 | Hold hand zones → repeated ADB swipes |
| Level Devil | Browser platformer | Hold hand zones → keyboard |

Both games can also be played with the keyboard directly.

## Subway Surfers

Real game in BlueStacks. Hand position drives it — there is no motion/swipe
detection, so returning your hand to the center never fires an unwanted
command. Holding a zone repeats that command every 300 ms: left/right edge =
lane change, center-high = jump, center-low = roll, center-mid = rest.

Numerical behavior (browser-side MediaPipe HandLandmarker, GPU delegate,
640x480 input, 30 FPS video):

- Side zones: engage `x < 0.24` (left) / `x > 0.76` (right), release back at
  `0.45` / `0.55` (mirrored frame x).
- Center vertical: jump at `y < 0.42` (release `> 0.50`), roll at `y > 0.62`
  (release `< 0.55`). Between them is the rest band — lowering your hand from
  the jump zone lands in rest, never a roll.
- Action repeat: 300 ms while a zone is held (server throttle 260 ms).
- End-to-end latency: detection (~33 ms) + POST (~5 ms) + ADB swipe (90 ms),
  roughly 100-140 ms.
- Hand acceptance: best-scoring hand, `hand_score >= 0.5`.

### Controls

| Gesture | Command | Key equivalent |
|---|---|---|
| Hold hand on left side | Swipe left (repeats) | Left arrow |
| Hold hand on right side | Swipe right (repeats) | Right arrow |
| Hold hand high in center | Jump (repeats) | Up arrow |
| Hold hand low in center | Roll (repeats) | Down arrow |
| Hand mid-center | Rest — nothing fires | - |

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
