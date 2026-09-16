# Using taptaptap with AI coding agents

`taptaptap` is new, so an agent has never seen the binary name in training data — but its command
grammar matches Meta's `idb`, which *is* widely documented online (`idb ui tap X Y`, `idb ui
describe-all`, `idb list-targets`, ...). An agent that already knows idb only needs one fact:
**swap `idb` for `taptaptap`.** See `docs/IDB-COMPAT.md` for the full mapping and deviations.
Three pieces make agents reach for it reliably.

## 1. Put the binary on PATH

Build it and link it — see the README's "Install" section for the full build command:

```bash
scripts/build.sh
mkdir -p ~/.local/bin
ln -sf "$(pwd)/build_products/taptaptap" ~/.local/bin/taptaptap   # ensure ~/.local/bin is on PATH
taptaptap --version
```

## 2. Install the skill (teaches the agent how to use it)

The sample skill lives at [`skills/taptaptap/SKILL.md`](../skills/taptaptap/SKILL.md). It covers the command reference,
the look → act → verify loop, recipes, gotchas, and what `xcrun simctl` should handle instead.

| Harness | Install |
|---|---|
| Claude Code | `ln -s "$PWD/skills/taptaptap" ~/.claude/skills/taptaptap`. Loaded on demand when a task matches the description. |
| Codex / other skill-aware harnesses | `ln -s "$PWD/skills/taptaptap" ~/.agents/skills/taptaptap`, or wherever the harness reads skills from |
| Project-scoped (any harness) | Copy to `<project>/.claude/skills/taptaptap/SKILL.md`, or reference it from the project's `AGENTS.md` |
| Harnesses without skills (e.g. Cursor) | Paste the skill's core-loop and command-reference sections into the project rules |

Symlinking keeps the skill in step with the repo. Copy it instead if you want it frozen.

## 3. Add a global rule (makes the agent choose it)

A skill teaches the tool; a rule stops the agent from defaulting to `idb` or installing something else. Add this to
your always-loaded instructions (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`,
Cursor Rules):

```markdown
## iOS Simulator UI automation
To tap, swipe, type, press buttons, read the accessibility tree, screenshot or record an iOS Simulator, use
`taptaptap` (on PATH). If you know idb, use the same commands with `taptaptap` in place of `idb`.
Load the `taptaptap` skill before first use.
- Never install or run idb, fb-idb, idb_companion, axe/AXe, or MCP UI-automation tools that wrap them.
- Use `xcrun simctl` for everything else (boot, install/launch apps, openurl, location, push, privacy, logs).
- Coordinates are iOS points from `taptaptap ui describe-all` frames, not screenshot pixels. Prefer --id/--label selectors.
```

## Why no MCP server?

Agents with a shell can already run `taptaptap` directly, and its output is text or JSON.
- **Surface area:** an MCP server would add a long-running process and a protocol layer to audit.
- **Dependencies:** it would usually pull in an SDK, which breaks the zero-dependency property.
- **When one makes sense:** only if a harness can't run shell commands, or you need to allow simulator control without allowing a general shell. Then build it into this repo as a local stdio, dependency-free `taptaptap mcp` subcommand and audit it like everything else.

## Check that it works

Ask an agent: *"Open Settings in the booted simulator, go to General → About, and tell me the iOS version."*
It should load the skill, run `xcrun simctl launch booted com.apple.Preferences`, then `taptaptap ui tap --label General`,
read the General screen with `taptaptap ui describe-all`, and tap the About row. Selectors can be ambiguous on that screen:
"About" matches several elements, so tapping the row's frame centre from describe-all (`taptaptap ui tap X Y`) is the reliable
route. It should never install or run idb.
