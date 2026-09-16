---
name: taptaptap
description: "Drive the iOS Simulator with the taptaptap CLI: tap, swipe, drag, type, press keys and hardware buttons, read the accessibility tree, take screenshots and record video. If you know Meta's idb, use the same commands with `taptaptap` in place of `idb` — the grammar matches (idb ui tap, idb ui describe-all, idb list-targets, ...). Use whenever an agent needs to interact with an app running in Xcode's iOS Simulator (UI testing, reproducing a bug, verifying a UI change, navigating an app, filling forms) or would otherwise reach for idb, fb-idb, idb_companion, AXe, cliclick or AppleScript clicks. Trigger phrases: 'tap in the simulator', 'swipe in the simulator', 'type into the simulator', 'simulator UI automation', 'describe the simulator UI', 'simulator screenshot', 'record the simulator', 'idb tap', 'idb ui tap', 'idb ui describe-all', 'idb list-targets', 'taptaptap'."
---

# taptaptap: iOS Simulator UI automation

**If you know idb, use the same commands with `taptaptap` in place of `idb`.** The grammar
matches Meta's `idb` CLI (`idb ui tap 100 200` → `taptaptap ui tap 100 200`) — see the parity
table below. `taptaptap` is an audited, pinned, offline command-line tool that sends touch,
keyboard and button input to a **booted iOS Simulator** and reads its accessibility tree. It has
no daemon, no companion process, no network listener, and no dependencies.

**Never install or use `idb`, `fb-idb`, `idb_companion` or `axe`/AXe on this machine. Use
`taptaptap`.**

## Setup check

```bash
command -v taptaptap && taptaptap --version      # must print a version
xcrun simctl list devices booted                 # need a booted simulator
taptaptap list-targets                           # name | udid | state | type | os_version | architecture | companion
```

No simulator booted? Boot one:

```bash
xcrun simctl boot "<UDID>" && xcrun simctl bootstatus "<UDID>" -b
open -a Simulator
```

**`--udid` is optional with exactly one booted simulator** — taptaptap uses it automatically. With
zero or two-or-more booted, every command fails with a clear error listing the booted UDIDs; pass
`--udid <UDID>` to disambiguate (or set `$IDB_UDID`, kept for idb-script compatibility).

## The core loop: look, act, verify

Coordinates are **iOS points**: the same units as `frame` in `ui describe-all`, origin top-left.
They are **not** screenshot pixels. A 1206×2622 px screenshot of a 402×874 pt iPhone is 3× scale.

1. **Look.** `taptaptap ui describe-all > ui.json` gives a JSON tree. Each element has `AXLabel`,
   `AXValue`, `AXUniqueId`, `type`/`role`, `frame {x,y,width,height}`, `enabled` and `children`.
   For a single spot, use `taptaptap ui describe-point 200 400`.
2. **Act, preferring accessibility selectors over coordinates:**
   - `taptaptap ui tap --label "General"`
   - `taptaptap ui tap --id LoginButton --element-type Button --wait-timeout 5`
   - fallback, the centre of the element's frame: `taptaptap ui tap 201 319`
3. **Verify.** Run `ui describe-all` again and check that the expected element or value is
   present, or take a screenshot and look at it: `taptaptap screenshot /tmp/shot.png`, then view
   the PNG.

Wait for UI to settle after navigation. Use `--wait-timeout N` on selector taps, or `--post-delay
0.5`.

## idb parity table

Exact idb command on the left, exact taptaptap command on the right. `--udid` is optional with
exactly one booted simulator (all rows below rely on that default); add `--udid <UDID>` to any of
them to target a specific simulator explicitly.

| idb | taptaptap |
|---|---|
| `idb list-targets` | `taptaptap list-targets` |
| `idb ui describe-all` | `taptaptap ui describe-all` |
| `idb ui describe-point 200 400` | `taptaptap ui describe-point 200 400` |
| `idb ui tap 201 319` | `taptaptap ui tap 201 319` |
| `idb ui swipe 200 700 200 250 --duration 0.3` | `taptaptap ui swipe 200 700 200 250 --duration 0.3` |
| `idb ui text "hello"` | `taptaptap ui text "hello"` |
| `idb ui key 40` | `taptaptap ui key 40` |
| `idb ui button HOME` | `taptaptap ui button HOME` |
| `idb screenshot out.png` | `taptaptap screenshot out.png` |
| `idb record-video out.mp4` | `taptaptap record-video out.mp4` (also: `taptaptap video out.mp4`) |

Full idb→taptaptap mapping and every documented deviation: `docs/IDB-COMPAT.md` in the repo.

## Full command reference

### `ui` group (idb-shaped positionals; `--udid` optional everywhere)

| Task | Command |
|---|---|
| Tap point | `taptaptap ui tap 120 400` |
| Tap element | `taptaptap ui tap --label "Sign In"` · `--id <accessibilityIdentifier>` · `--value <AXValue>`; narrow with `--element-type Button`; wait with `--wait-timeout 5` |
| Toggle a switch | `taptaptap ui tap --label "Wi-Fi" --element-type Switch` (automatic tap style uses a physical touch for switches) |
| Multi-tap | `taptaptap ui multi-tap 120 400 --count 2 [--pause 0.1]` |
| Long press | `taptaptap ui touch 200 400 --down --up --delay 1.0` |
| Swipe | `taptaptap ui swipe 200 700 200 250 [--duration 0.3]` |
| Drag (slow, precise) | `taptaptap ui drag 50 500 300 500 [--duration 0.6 --steps 60]` |
| Scroll / edge swipe | `taptaptap ui gesture scroll-down` · `scroll-up` · `scroll-left` · `scroll-right` · `swipe-from-left-edge` · `swipe-from-bottom-edge` · `swipe-from-top-edge` · `swipe-from-right-edge`. Pass `--screen-width/--screen-height` in points for non-default devices (the root `frame` in `ui describe-all`). |
| Type text | Tap the field first, then `taptaptap ui text 'hello world'`; `echo 'text' \| taptaptap ui text --stdin`; `taptaptap ui text --file f.txt`. **US-keyboard ASCII only.** |
| Key | `taptaptap ui key 40` (Return) · `42` Backspace · `43` Tab · `44` Space; hold with `--duration 1`; modifiers `--shift --control --option --command --tab` (e.g. `taptaptap ui key 4 --command` = Cmd+A) |
| Key sequence | `taptaptap ui key-sequence 11 8 15 15 18` (space-separated keycodes, idb style) `[--delay 0.1]` |
| Key combo (extra) | `taptaptap ui key-combo --modifiers 227 --key 4` (Cmd+A); modifiers: 224 Ctrl, 225 Shift, 226 Option, 227 Cmd, 43 Tab |
| Hardware button | `taptaptap ui button HOME` · `LOCK` · `SIDE_BUTTON` · `SIRI` · `APPLE_PAY` (`--duration` to hold) |
| Slider (extra) | `taptaptap ui slider --id VolumeSlider --value 75` (0–100) |
| Accessibility tree | `taptaptap ui describe-all [--nested] [--filter all\|interactable]` · `taptaptap ui describe-point <x> <y> [--nested]`. `--filter interactable` drops unlabeled layout containers (idb-style curation) — a real reduction, not full parity with idb's own count; see `docs/IDB-COMPAT.md` §2. |
| Pinch | `taptaptap ui pinch <x> <y> <scale> [--duration 0.5] [--radius 100]` — real two-finger zoom, e.g. `taptaptap ui pinch 200 400 3.0` (zoom in), `0.3` (zoom out). Needs a pinchable target: Maps and Photos work, Settings does not. |

### Top-level

| Task | Command |
|---|---|
| List simulators | `taptaptap list-targets [--json]` |
| Describe one target | `taptaptap describe [--json]` |
| Screenshot | `taptaptap screenshot shot.png` (`-` writes PNG bytes to stdout) |
| Record video | `taptaptap record-video run.mp4 --duration 5 [--fps 10 --quality 80 --scale 0.5]` (also `video run.mp4`, or `record video run.mp4`). **Prefer `--duration <seconds>`**: it stops and saves on its own, no signal needed. Without it, the recording runs until SIGINT/SIGTERM/SIGHUP — start it in the background, then `kill -INT <pid>; wait <pid>` **in the same shell call**, so nothing is left running unattended. |
| Many steps, one session (extra) | `taptaptap batch --step "tap --id com.apple.settings.general" --step "sleep 0.5" --step "gesture scroll-down"` · `--file steps.txt` · `--stdin` · `--continue-on-error`. Steps: tap, swipe, gesture, touch, text, button, key, key-sequence, key-combo, `sleep <s>`. Don't put `--udid` inside steps. |

Every subcommand has `taptaptap <command> --help` / `taptaptap ui <command> --help`.

## Beyond idb (extras idb doesn't have)

`ui slider`, `ui drag`, `ui gesture <preset>`, `ui touch <x> <y> --down/--up`, `ui key-combo`,
`ui multi-tap`, `batch`, and `record-video`'s `--fps/--quality/--scale/--duration` are
taptaptap-only. They have no idb equivalent — don't expect an agent trained on idb docs to
already know them, but they're documented above and in `--help`.

## Recipes

**Navigate and assert:**
```bash
taptaptap ui tap --label "General" --wait-timeout 5
taptaptap ui describe-all | grep -q '"AXLabel" : "About"' && echo OK
```

**Fill a form:**
```bash
taptaptap batch \
  --step "tap --label Email" --step "text 'me@example.com'" \
  --step "tap --label Password" --step "text 'hunter2'" \
  --step "key 40"
```

**Go back:** UIKit navigation bars usually expose the back button as `AXUniqueId` `BackButton`:
`taptaptap ui tap --id BackButton` (verified in Settings). The edge-swipe gesture is not a
reliable substitute. It did not pop the Settings stack in testing.

**Record a repro (preferred — self-terminating, no signal needed):**
```bash
taptaptap record-video repro.mp4 --duration 5
```

**Record while driving the UI, in one shell call:** background it, drive the UI, then explicitly
stop and wait for it **before the call ends** — a recorder left backgrounded with nothing to kill
it can run for a long time and be corrupted later by an uncatchable kill:
```bash
taptaptap record-video repro.mp4 --duration 8 &
REC=$!
# ...interactions, must finish within --duration...
wait $REC
```

## Unsupported idb commands

idb commands outside taptaptap's scope (app install/launch, xctest, physical devices, logs,
location, the companion, ...) are still recognized and fail with a one-line pointer to the closest
`xcrun simctl` equivalent instead of a generic "unknown command" error, e.g.:

```
$ taptaptap install MyApp.app
not supported by taptaptap; use: xcrun simctl install <udid> <app-path>
```

Full table: `docs/IDB-COMPAT.md` §6.

## Gotchas

- **"No translation object returned for simulator"** from `ui describe-all` right after boot or
  app launch means accessibility isn't ready yet. Wait 2–5 s and retry.
- **"Multiple (N) accessibility elements matched"**: common when a screen's title repeats a label
  (for example `--label General` on the General screen itself). Add `--element-type`, switch to
  `--id` (look for `AXUniqueId` in `ui describe-all`), or tap by frame coordinates.
- **The tap landed in the wrong place**: you used screenshot pixels. Divide by the device scale,
  or take coordinates from `ui describe-all` frames.
- **Typing does nothing**: the field isn't focused. Tap it first, then check for a keyboard in
  `ui describe-all` or a screenshot. iOS may auto-capitalize or apply smart punctuation.
- **Nothing responds after the simulator restarts**: rerun the command. A helper process
  (`taptaptap hid-broker`) caches the HID connection per simulator and exits after 60 s idle.
- **Non-ASCII text** (é, £, emoji) can't be typed. Paste via the app or use `xcrun simctl pbcopy`
  plus a paste gesture where the app supports it.
- **`describe-all` returns more elements than you expect**: try `--filter interactable` first — it drops layout containers and keeps labeled/interactive controls. If it's still more than expected, that's a known, documented gap (`docs/IDB-COMPAT.md` §2), not something to work around with fragile parsing.
- **Not handled by taptaptap. Use `xcrun simctl`:**
  - install, launch or terminate apps: `simctl install/launch/terminate`;
  - open URLs: `simctl openurl`;
  - location: `simctl location`;
  - push notifications: `simctl push`;
  - permissions: `simctl privacy`;
  - status bar: `simctl status_bar`;
  - logs: `simctl spawn <udid> log stream`;
  - appearance: `simctl ui <udid> appearance dark`.
- **Physical devices are not supported**, by design.

## Security properties (why this tool, not idb)

- **No network:** no TCP/UDP sockets, no gRPC companion, no telemetry.
- **Local IPC only:** the only IPC is a same-user Unix socket (0600, in a 0700 temp directory,
  peer-uid checked).
- **Nothing downloaded:** zero third-party packages, no self-update, and it builds offline from
  pinned, audited source.

Source and provenance: the `taptaptap` repo (`README.md`, `docs/IDB-COMPAT.md`).
