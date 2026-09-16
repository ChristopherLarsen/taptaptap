# taptaptap

An audited, pinned, offline-buildable replacement for [idb](https://github.com/facebook/idb)'s
Simulator input path — **and its command grammar**. If you already know idb, you already know
taptaptap: `idb ui tap 100 200` becomes `taptaptap ui tap 100 200`. Tap, swipe, touch, drag,
pinch, gesture, text, key/key-sequence/key-combo, hardware buttons, the accessibility tree
(`ui describe-all`/`ui describe-point`, with idb's `--nested` and `--filter interactable`),
screenshots and video recording. One pure SwiftPM package, **zero package dependencies**, based on the work
[cameroncooke/AXe](https://github.com/cameroncooke/AXe) and
[cameroncooke/idb](https://github.com/cameroncooke/idb), a fork of Meta's idb.

**Verified against real idb, live and side by side, not just against its source** — every
command it claims idb parity for was checked against a genuine idb install on the same simulator.

## Why this exists

Stock idb runs `idb_companion`, an unauthenticated gRPC server bound to all interfaces on TCP
10882, and its Python client pulls in `grpclib`/`h2`/`multidict` plus 21 SwiftPM packages on the
companion side. taptaptap has no network listener
anywhere (verified with `lsof` on every build), no third-party dependency
(`Package.swift`: `dependencies: []`, no `Package.resolved`), and every surviving line has been
audited.

## Install

There's no prebuilt release yet — build it yourself. That's not a shortcut you're skipping: it's
the same offline, zero-dependency build every verification in this repo was run against, and it
takes under a minute.

```bash
git clone https://github.com/ChristopherLarsen/taptaptap.git
cd taptaptap
scripts/build.sh
```

Release configuration, universal (`arm64` + `x86_64`), ad-hoc signed, fully offline. Output:
`build_products/taptaptap`. Put it on your `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/build_products/taptaptap" ~/.local/bin/taptaptap
taptaptap --version
```

To prove the offline claim yourself, deny the build network access and watch it still succeed:

```bash
sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' scripts/build.sh
```

(`scripts/build.sh` always passes `--disable-sandbox` to `swift build`: SwiftPM's own plugin
sandbox cannot nest inside `sandbox-exec`. That flag does not weaken the offline guarantee; it
works around a harness limitation, and the network-deny wrapper above is what actually proves no
network call happens.)

Record your build's hash (`shasum -a 256 build_products/taptaptap`) if you want to compare it
against a future build or share it for someone else to verify.

## Quick start

```bash
taptaptap list-targets                        # see your booted simulators
taptaptap ui describe-all                      # dump the accessibility tree (JSON)
taptaptap ui tap 100 200                       # tap a point
taptaptap ui tap --label "Sign In"             # tap by accessibility label instead
taptaptap screenshot out.png                   # save a screenshot
```

`--udid` is optional everywhere when exactly one simulator is booted. Full command-by-command idb
mapping and every intentional deviation: `docs/IDB-COMPAT.md`.

`taptaptap --help` lists every idb command name, including ones taptaptap doesn't implement
(`install`, `boot`, `xctest`, `log`, …) — each of those fails immediately with a one-line pointer
to the right `xcrun simctl` equivalent, rather than being silently unrecognized. This is
intentional: an agent or script that mistypes or guesses an idb command it half-remembers gets a
precise correction instead of a generic "unknown command." See `docs/IDB-COMPAT.md` for the full
list and their replacements.

## Using it from AI agents

Agents learn `taptaptap` from a skill, not from training data — it's new, so nothing has seen the
binary name before, but the command grammar matches idb, which is widely documented. See
[`docs/AGENT-SETUP.md`](docs/AGENT-SETUP.md) for the three-step setup any harness needs: put the
binary on `PATH`, install the skill, add one global rule. It also covers why there's no MCP server.

**The skill itself, ready to use:** [`skills/taptaptap/SKILL.md`](skills/taptaptap/SKILL.md) — drop
it into `~/.claude/skills/taptaptap/`, `~/.agents/skills/taptaptap/`, or your harness's equivalent
skills directory, and any Claude Code, Codex, or other skill-aware agent picks it up.

## Test

```bash
scripts/dev-test.sh          # debug build + swift test, offline (includes the idb-style goldens)
scripts/check-goldens.py build_products/taptaptap Tests/Goldens/xcode-26.5-17F42_ios-26.5-23F77/stable/cases --version-skip
scripts/e2e-settings.sh build_products/taptaptap <evidence-dir> <booted-simulator-udid>
```

`Tests/Goldens/.../stable/cases` is taptaptap's own idb-style command-surface snapshot,
re-recorded (via `scripts/record-goldens.py`) whenever the surface changes.



## Security invariants (checked every gate run)

- No IPv4/IPv6 socket, ever: `lsof` on every live process (CLI client, `hid-broker`,
  `record-video`) shows AF_UNIX only.
- The HID broker listens on a 0600 unix socket inside a 0700 directory
  (`$TMPDIR/taptaptap-hid-<uid>/`), checks `getpeereid` before completing its handshake, prunes
  stale sibling sockets on startup, and rejects non-finite coordinates.
- The build has zero package dependencies and succeeds under a network-deny sandbox.
- `DEVELOPER_DIR` is validated against Xcode's own shape (`usr/bin/xcodebuild` present) before any
  private framework loads from it. Control of the process environment is not treated as a security
  boundary (whoever controls it already controls what code an ordinary tool loads) — this bound
  exists for robustness against misconfiguration, not against an attacker with that level of access.

## What's not here

Physical devices, the debugger/DAP, xctest/instruments/xctrace, crash logs, file/app/process-spawn
commands, and anything that talks to a network. Each prints a one-line `xcrun simctl` pointer
instead of doing nothing or crashing — see "Quick start" above and `docs/IDB-COMPAT.md` 