# IDB compatibility spec (Phase 4)

Christopher authorized Phase 4 on 2026-09-15: make `taptaptap`'s command grammar match Meta's
`idb` CLI closely enough that "if you know idb, swap `idb` for `taptaptap`" is literally true.
The AXe-style grammar (`tap -x … -y …`, `describe-ui`, `list-simulators`, …) is removed, not kept
alongside. The binary stays named `taptaptap`; there is no `idb` alias. Version `0.2.1`
(bumped from `0.2.0` in Phase 5, a bugfix pass -- no command-grammar change).

Source of truth: the pinned idb Python CLI, from Cameron Cooke's idb fork
(`github.com/cameroncooke/idb`) at commit `604c51013438f0c3603b720a05a44b7c5b8f286d`
specifically its `idb/cli/` directory — not bundled in this repository (clone it yourself at
that commit to check any citation below). Cited paths below are relative to that
directory unless stated otherwise.

## 1. Command tree

idb's `main.py` (`gen_main`, lines ~190–319) registers most HID/accessibility commands inside a
`CommandGroup(name="ui", …)` (`main.py:259–274`); `screenshot`, `video`/`record-video`, and
`list-targets`/`describe` stay top-level. taptaptap mirrors that shape exactly, plus its own
extras nested under `ui` too (Christopher's decision: "re-expressed in idb style").

```
taptaptap
├── list-targets [--json] [--udid]
├── describe [--json] [--udid]
├── screenshot <dest-path|-> [--udid]
├── video <output-file> [--udid]            (aliases: record-video, "record video")
├── batch …                                 (extra, kept)
├── hid-broker …                            (internal, kept, hidden from help)
├── ui
│   ├── tap [<x> <y>] [--duration] [--id|--label|--value [--element-type]]
│   │       [--wait-timeout] [--poll-interval] [--tap-style] [--pre-delay] [--post-delay]
│   ├── multi-tap <x> <y> [--count] [--duration] [--pause]
│   ├── pinch <x> <y> <scale> [--duration] [--radius]
│   ├── swipe <x1> <y1> <x2> <y2> [--duration] [--delta] [--pre-delay] [--post-delay]
│   ├── text <text> [--stdin] [--file]
│   ├── key <keycode> [--duration] [--shift] [--control] [--option] [--command] [--tab]
│   ├── key-sequence [<keycode> ...]
│   ├── button {APPLE_PAY,HOME,LOCK,SIDE_BUTTON,SIRI} [--duration]
│   ├── describe-all [--nested] [--filter {all,interactable}]
│   ├── describe-point <x> <y> [--nested]
│   ├── slider [--id|--label] [--element-type] --value <0-100> [--wait-timeout] [--poll-interval]   (extra)
│   ├── drag <x1> <y1> <x2> <y2> [--duration] [--steps] [--pre-delay] [--post-delay]                (extra)
│   ├── gesture <preset> [--screen-width] [--screen-height] [--duration] [--delta]
│   │           [--pre-delay] [--post-delay]                                                        (extra)
│   ├── touch <x> <y> [--down] [--up] [--delay]                                                     (extra)
│   └── key-combo --modifiers <m,m,...> --key <keycode>                                             (extra)
└── <unsupported idb command> → prints "not supported by taptaptap; use: xcrun simctl <cmd>",
    exit 1 (§5)
```

Every `ui`/`screenshot`/`video`/`list-targets`/`describe` command takes an optional `--udid` (§3).

## 2. Per-command mapping (idb source → taptaptap)

| Command | idb source | Positionals / options | Deviation |
|---|---|---|---|
| `ui tap` | `hid.py:19-35` `TapCommand` | `x y` ints, `--duration` | Coordinates accepted as any finite real (not integer-only) — taptaptap's existing sub-pixel HID precision, a superset of idb's `int`. `x`/`y` become optional when `--id`/`--label`/`--value` is given (taptaptap extra, absent from idb — `hid.py` has no selector concept). `--duration` has no default in idb (`None` → companion default); taptaptap likewise leaves it `nil` and lets the HID layer pick. |
| `ui multi-tap` | `hid.py:38-72` `MultiTapCommand` | `x y`, `--count=2`, `--duration`, `--pause=0.1` | New command (implemented as repeated `tapAt` composite events with `--pause` delays — cheap on the existing single-finger HID primitive). |
| `ui pinch` | `hid.py:235-268` `PinchCommand` | `x y scale`, `--duration=0.5`, `--radius=100.0` | Implemented (Phase 6): `FBSimulatorHIDEvent.pinchAt(x:y:scale:duration:radius:)` builds a `.twoFingerTouch`-based composite (interpolated two-finger touch-down/move/up), ported verbatim from the pinned idb source into `FBSimulatorHIDEvent.swift`, with a matching `sendTwoFingerTouch` on both the Indigo and DTUHID transports. |
| `ui swipe` | `hid.py:191-232` `SwipeCommand` | `x_start y_start x_end y_end`, `--duration`, `--delta` | taptaptap keeps its own `--pre-delay`/`--post-delay` extras (idb has none). |
| `ui text` | `hid.py:174-188` `TextCommand` | `text` | taptaptap keeps `--stdin`/`--file` (extras; idb's `text` only takes the positional). Command renamed from taptaptap's old `type` to idb's `text` (also renames the batch step keyword, §6). |
| `ui key` | `hid.py:100-150` `KeyCommand` | `key`, `--duration`, `--shift --control --option --command --tab` | Modifier flags are new on `key` (previously only on the separate `key-combo` extra). Implemented by building the same down/press/up event sequence idb's `key_press_with_modifiers_to_events` describes (modifiers down, key press, modifiers up in reverse). |
| `ui key-sequence` | `hid.py:153-171` `KeySequenceCommand` | `key_sequence` (`nargs="*"`, space-separated) | Changed from taptaptap's old `--keycodes 1,2,3` (comma option) to idb's positional space-separated list. Zero arguments parses successfully and is a no-op, matching idb's `nargs="*"` (not an error). |
| `ui button` | `hid.py:75-97` `ButtonCommand` | `button` (enum), `--duration` | Enum spellings changed to idb's `HIDButtonType` names (`common/types.py:111-116`): `APPLE_PAY, HOME, LOCK, SIDE_BUTTON, SIRI` (was kebab-case `apple-pay` etc.). `FBSimulatorHIDButton` raw values already match idb's enum order 1–5, so this is a spelling change only, not a remap. |
| `ui describe-all` | `accessibility.py:15-35` | `--nested`, `--filter` | Output is already raw JSON in both (`print(info.json)` / taptaptap's `AccessibilityFetcher`); no `--json` flag needed here, matching idb exactly. **`--nested` is implemented (Phase 6)**: default `false` returns a flat array (each element serialized independently, no `children` key — shape now matches idb's own default exactly); `--nested` returns the tree with `children`, as before. **`--filter <all\|interactable>` is implemented (Phase 7, structural heuristic only)**: idb's opt-in `.interactable` narrowing — keep an element with a non-empty label, a non-empty identifier, or an interactable role, hoisting kept descendants into the place of anything dropped — ported from `facebook/idb` v1.5.7's `AccessibilityElementFiltering.swift`/`AXRoleVocabulary.swift`. idb's *other* narrowing, an opt-in per-element "interactable verdict" hit-test against the backend, is **not** ported (no reference implementation in the pinned tree; out of Phase 7's scope by design) — this is a heuristic subset of idb's `.interactable`, not full parity with it. idb wires `--filter` onto `describe-all` only, not `describe-point` (confirmed against `AccessibilityInfoAtPointCommand` in `accessibility.py`, which never calls `_add_filter_arg`) — taptaptap matches, `describe-point` has no `--filter`. **Element count: diminished, not closed.** Verified live 2026-09-15 on the same General screen as the original A/B: `--filter interactable` reports 75 elements, down from the unfiltered 203 (73 labeled) — a real ~2.7x reduction that roughly tracks the labeled count — but still well above idb's observed 14. **Root cause remains the one found in Phase 6**: real idb's own *default* (unfiltered) traversal on this screen is already 14 elements, one layer below any opt-in filter, so no filter ported at this layer — structural or verdict-based — can close a gap that originates in the traversal itself. Portable next step if the full gap still matters: investigate why the pinned `AccessibilityPlatformTranslation`-based translator returns ~5x more elements than whatever mechanism real idb 1.5.7's default traversal uses — genuinely new investigation, not a recovery port. |
| `ui describe-point` | `accessibility.py:38-62` | `x y`, `--nested` | Changed from taptaptap's old `--point "x,y"` string option to idb's two positionals. **`--nested` is implemented (Phase 6)**: default `false` omits the `children` key entirely (byte-shape-verified against idb's own `03-idb-describe-point.json`, which also has no `children` key); `--nested` adds `children: []` (a single element has none). **`traits` is always `[]`**, never idb's real trait list — intentional (`AccessibilityFetcher.swift:404-407`): populating it breaks the hierarchy under Xcode 27's private nested serializer, so the existing public shape is kept. Verified live against real idb 2026-09-15. |
| `list-targets` | `target.py:170-202` | `--only` (device-type filter), `--json` | `--only` is **not implemented** (undeclared → unknown-option error). taptaptap only ever lists simulators (device support is out of scope per the charter), so the filter has nothing to select between; documented deviation rather than a fake no-op flag. Human row format matches `human_format_target_info` (`format.py:215-227`): `name | udid | state | type | os_version | architecture | <companion>`; with no companion concept, the last field is always `No Companion Connected`, which is what idb itself prints for an unconnected target — not a fabricated field. |
| `describe` | `target.py:139-163` | `--diagnostics`, `--json` | `--diagnostics` accepted and ignored (taptaptap has no extra diagnostics channel beyond what `describe` already reports). |
| `screenshot` | `screenshot.py:19-49` | `dest_path` (positional; `-` → stdout) | Changed from taptaptap's old `--output <path>` option (with a generated default filename) to idb's required positional, including `-` for stdout. |
| `video` / `record-video` | `video.py:23-43` (`name="video"`, `aliases=["record-video"]`) + `main.py:233-238` (`record` group wrapping `video`) | `output_file` (positional) | All three spellings accepted: `video OUT`, `record-video OUT`, `record video OUT` (§6 on how). taptaptap's `--fps`/`--quality`/`--scale` extras are kept (idb's `video` has none; those live on the unrelated `video-stream`, which taptaptap does not implement — no raw H264 stream support, and streaming would need a long-lived transport this project's no-network-listener rule rules out anyway). **`--duration <seconds>` is also taptaptap-only** (1-3600): stops and finalizes the file automatically, no signal needed. **Prefer it** over `& ... kill -INT` in a single shell call — a recorder backgrounded and never explicitly signaled (or orphaned when its shell exits) can run for a long time and then be corrupted by an uncatchable kill later (Phase 5 F1, TESTING.md). Without `--duration`, the process still finalizes cleanly on SIGINT, SIGTERM, or SIGHUP (all three are caught and write the moov atom before exiting), but SIGKILL cannot be caught by any process. |
| `ui slider`, `ui drag`, `ui gesture`, `ui touch`, `ui key-combo`, `batch` | — (no idb equivalent) | unchanged shape, `-x/-y`-style flags on `drag`/`touch` replaced by idb-shaped positionals for consistency | Extras, kept per taptaptap's scope and Christopher's brief; documented under "beyond idb" in the skill, not claimed as idb parity. |

## 3. `--udid` resolution

idb: `ClientCommand.add_parser_arguments` (`idb/cli/__init__.py:127-133`) declares
`--udid` defaulting to `$IDB_UDID`; `_get_client` (`idb/cli/__init__.py:52-68`) passes it to
`ClientManager.from_udid`, which — per idb's own docs — resolves to the sole booted target when
`udid` is `None` and exactly one is booted.

taptaptap's resolution order (all `ui`/`screenshot`/`video`/`list-targets`/`describe` commands):
1. explicit `--udid VALUE`;
2. the `IDB_UDID` environment variable (kept for idb-script compatibility — dropping it would
   silently break a script that already exports it);
3. the sole booted simulator, if exactly one is booted;
4. otherwise: fail with a one-line error listing every booted UDID (or "no simulator is booted")
   and asking for `--udid`.

Implemented once as a shared `TargetResolver.resolveUDID(explicit:environment:bootedSimulators:)`
so it's unit-testable against an injected booted-simulator list (0, 1, 2+ cases) without booting
real simulators for every case; one live spot-check confirms the error text against the real
`simctl` state.

## 4. Global options — accepted vs. not

idb's `BaseCommand`/`ClientCommand` (`idb/cli/__init__.py:71-133`) put `--log`, `--json`,
`--reason`, `--udid`, plus root-parser-level `--companion`, `--companion-path`, `--companion-tls`,
`--compression`, `--no-prune-dead-companion` on every command, because idb talks to a possibly
remote `idb_companion` over gRPC.

taptaptap has no companion process and no network transport (hard security gate). Accepting those
flags silently would be dishonest — they'd imply a companion/TLS/compression story that doesn't
exist. Decision:
- `--udid`: implemented everywhere (§3) — it's the one flag that maps onto a real concept (which
  local simulator).
- `--json`: implemented where it changes output — `list-targets`, `describe`. (`ui describe-all`/
  `ui describe-point` already always print raw JSON, matching idb exactly with no flag needed.)
- `--log`, `--reason`, `--companion`, `--companion-path`, `--companion-tls`, `--compression`,
  `--no-prune-dead-companion`, `--only`: **not accepted.** An agent that types one gets a normal
  "unknown option" error, not silent acceptance. Documented here rather than silently
  under-delivering the "same options" promise from the plan.

## 5. Unsupported idb commands

Commands idb has that taptaptap deliberately doesn't implement (install/launch/xctest/devices/
etc. — see the charter's "Out of scope, deleted" list) are still **recognized** at the top level
so an agent gets a one-line, actionable pointer instead of a generic "unknown command" error, exit
code 1:

| idb command(s) | Message points to |
|---|---|
| `install`, `uninstall`, `list-apps`, `launch`, `terminate` | `xcrun simctl install/uninstall/listapps/launch/terminate` |
| `open` | `xcrun simctl openurl` |
| `log` | `xcrun simctl spawn <udid> log stream` |
| `location` | `xcrun simctl location` |
| `boot`, `shutdown`, `erase`, `create`, `clone`, `delete`, `delete-all` | `xcrun simctl boot/shutdown/erase/create/clone/delete` |
| `connect`, `disconnect` | not applicable — taptaptap has no companion process; talks to the simulator directly |
| `xctest`, `crash`, `instruments`, `xctrace`, `dap`, `debugserver` | `xcrun simctl spawn` / Xcode's own test runner (out of the charter's kept scope) |
| `file` | `xcrun simctl get_app_container` / direct filesystem access to the simulator's data dir |
| `focus`, `approve`, `revoke`, `contacts`, `photos`, `keychain`, `notification`, `memory`, `settings`, `shell`, `framework`, `dsym`, `dylib`, `media` | `xcrun simctl privacy/notify_post/spawn` (varies by command; each stub names the closest `simctl` verb) |

These are real subcommands (parse their own `--help`), not a catch-all — each swallows its
declared idb arguments (so `taptaptap install /path/app.app --udid X` doesn't also throw a
confusing "unknown option --udid") and exits 1 with the pointer. `connect`/`disconnect` get a
message explaining there's no companion to connect to, rather than a `simctl` pointer that doesn't
exist.

## 6. Implementation notes

- **Parser nesting.** `TapTapTapArguments`'s `CommandRunner.run(_:arguments:)`
  (`Sources/TapTapTapArguments/Running.swift:13-27`) resolved exactly **one** level of
  `subcommands` before parsing the remainder against the matched type directly — verified by
  reading `CommandArgumentsParser.parse` (`Parsing.swift:199`, doc comment: "no subcommand
  dispatch") and by the fact only `runHelp` (`Running.swift:58-89`) looped. `taptaptap ui tap 100
  200` needs two levels (`taptaptap` → `ui` → `tap`). Fixed by turning the one-shot dispatch into
  a loop that walks `stack.last!.configuration.subcommands` until a token doesn't match, then
  parses the remaining tokens against the deepest matched type — the same shape `runHelp` already
  used. This is a change to the audited parser engine, with unit tests for two-level dispatch,
  `help ui tap`, and `ui --help`.
- **`video`/`record-video`/`record video` aliasing.** `CommandConfiguration` has no alias list.
  Rather than add one (more surface on the just-verified nesting change), three thin
  `AsyncParsableCommand` structs (`Video`, `RecordVideo`, and a `Record` group wrapping a third)
  share one implementation function; each just declares its own `commandName`.
- **Batch steps already inherit this for free.** `BatchStepParser`
  (`Sources/TapTapTapCLI/Utilities/Batch/BatchStepParser.swift`) parses each step's tokens by
  calling the real command struct's `parseAsRoot(_:)` — e.g. a `tap` step is parsed by `Tap.self`.
  Renaming `Tap`'s/`Swipe`'s/etc. declared arguments to idb's positional shape updates batch step
  syntax automatically; the only `BatchStepParser` change needed is renaming the `type` step
  keyword to `text` (`BatchStepKind`) to track the command rename.
- **Button enum.** `ButtonType` (`Sources/TapTapTapCLI/Commands/Button.swift`) raw values change
  from kebab-case (`apple-pay`) to idb's `HIDButtonType` spellings (`APPLE_PAY`). The underlying
  `FBSimulatorHIDButton` raw values (1–5) already match idb's enum order, so this is a rename, not
  a remap.

## 7. Goldens — what survives, what's replaced

Two golden sets exist (`Tests/TapTapTapTests/GoldenCaseTests.swift`):

- **`Tests/Goldens/parser/cases`** (71 cases): recorded from AXe's real `swift-argument-parser`
  build, using AXe's own AXe-style command surface (`tap -x5 -y5 …`, `describe-ui`, …) purely as a
  fixture vehicle. This is the proof that the
  hand-written `TapTapTapArguments` engine is behaviorally identical to `swift-argument-parser`.
  Phase 4 removes the AXe-style commands these cases invoke, so **they can no longer run against
  the idb-style binary** — the commands (`tap -x…`, `describe-ui`, `list-simulators`, …) don't
  exist anymore. The files are **left on disk, untouched, unexecuted** (git history already
  preserves their evidentiary value); `GoldenCaseTests.caseDirectories`
  drops this set from the active suite. This is a direct, foreseeable, and previously-approved
  consequence of "remove the AXe-style syntax entirely" (PHASE4-PLAN.md decision 2) — not a silent
  loss. Ongoing regression coverage for the parser *engine's* mechanics (long/short options, `=`,
  `--`, repeated-array options, enum conversion errors, help layout, error text) moves to a new
  synthetic-fixture suite in `Tests/TapTapTapArgumentsTests` that declares its own tiny throwaway
  command tree independent of taptaptap's real commands, so it keeps proving the engine and stops
  being coupled to whatever surface the CLI happens to expose this phase.
- **`Tests/Goldens/xcode-26.5-17F42_ios-26.5-23F77/stable/cases`**: taptaptap's own
  command-surface snapshot, already regenerated once for the 3f rename ("goldens-reflow"). This is
  the set PHASE4-PLAN.md step 3 means by "replace the AXe-parity goldens with idb-compat goldens":
  re-recorded (not hand-authored) against the real idb-style binary once it's built, using a new
  `scripts/record-goldens.py` that captures `argv → stdout/stderr/exit-code` for a curated case
  list (help text, argument/validation errors, unknown-option errors, enum errors, `--json`
  output, the unsupported-command pointers, target-resolution errors that don't need a booted
  simulator, `version`). The `--version-skip`/`@UDID@` conventions in `check-goldens.py` are kept.

## 8. Version

`Sources/TapTapTapCLI/Types/Version.swift`'s `VERSION` constant bumps to `0.2.0`.
