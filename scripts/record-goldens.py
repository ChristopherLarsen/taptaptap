#!/usr/bin/env python3
"""Record command-surface goldens (argv/stdin -> stdout/stderr/exit code) by running the real
built binary. Phase 4 (docs/IDB-COMPAT.md §8): the "stable/cases" set characterizes taptaptap's
own idb-style command surface (help text, argument/validation errors, enum errors, defaults) and
is re-recorded whenever that surface changes -- it is NOT the swift-argument-parser-parity
fixture (that's Tests/Goldens/parser/cases, frozen and never re-recorded, see GoldenCaseTests.swift).

Usage: record-goldens.py <binary> <output-cases-dir>
Cases are defined in CASES below: (name, argv-without-binary, stdin-or-None).
An argv token "@UDID@" is left literal (check-goldens.py substitutes it at verification time);
GoldenCaseTests.swift skips any case whose argv contains "@UDID@" since swift test has no
guaranteed booted simulator. Keep this list mostly free of @UDID@ cases so the default `swift
test` run exercises them.
"""
import os
import subprocess
import sys

CASES: list[tuple[str, list[str], bytes | None]] = [
    # Root
    ("version", ["--version"], None),
    ("help", ["--help"], None),
    ("help-command", ["help"], None),
    ("help-ui", ["help", "ui"], None),
    ("help-ui-tap", ["help", "ui", "tap"], None),

    # list-targets / describe
    ("help-list-targets", ["list-targets", "--help"], None),
    ("error-list-targets-unknown-option", ["list-targets", "--axe-invalid-option"], None),
    ("help-describe", ["describe", "--help"], None),

    # screenshot
    ("help-screenshot", ["screenshot", "--help"], None),
    ("error-screenshot-missing-value", ["screenshot"], None),
    ("error-screenshot-unknown-option", ["screenshot", "out.png", "--axe-invalid-option"], None),

    # video / record-video / record video
    ("help-video", ["video", "--help"], None),
    ("help-record-video", ["record-video", "--help"], None),
    ("help-record", ["record", "--help"], None),
    ("help-record-video-group", ["record", "video", "--help"], None),
    ("error-video-missing-value", ["video"], None),
    ("error-record-video-missing-value", ["record-video"], None),
    ("validation-record-video-fps", ["record-video", "out.mp4", "--fps", "0"], None),

    # batch
    ("help-batch", ["batch", "--help"], None),
    ("validation-batch-source", ["batch"], None),
    ("stdin-batch-empty", ["batch", "--stdin"], b""),

    # ui group
    ("help-ui-group", ["ui", "--help"], None),

    # ui tap
    ("help-ui-tap-detail", ["ui", "tap", "--help"], None),
    ("error-ui-tap-no-coords-no-selector", ["ui", "tap"], None),
    ("error-ui-tap-unknown-option", ["ui", "tap", "1", "2", "--axe-invalid-option"], None),
    ("validation-ui-tap-coordinates", ["ui", "tap", "-1", "5"], None),

    # ui multi-tap
    ("help-ui-multi-tap", ["ui", "multi-tap", "--help"], None),
    ("error-ui-multi-tap-missing-value", ["ui", "multi-tap"], None),

    # ui pinch
    ("help-ui-pinch", ["ui", "pinch", "--help"], None),
    ("error-ui-pinch-missing-value", ["ui", "pinch"], None),

    # ui swipe
    ("help-ui-swipe", ["ui", "swipe", "--help"], None),
    ("error-ui-swipe-missing-value", ["ui", "swipe"], None),
    ("error-ui-swipe-unknown-option", ["ui", "swipe", "1", "2", "3", "4", "--axe-invalid-option"], None),

    # ui text
    ("help-ui-text", ["ui", "text", "--help"], None),
    ("error-ui-text-no-input", ["ui", "text"], None),

    # ui key
    ("help-ui-key", ["ui", "key", "--help"], None),
    ("error-ui-key-missing-value", ["ui", "key"], None),
    ("validation-ui-key-value", ["ui", "key", "999"], None),

    # ui key-sequence
    ("help-ui-key-sequence", ["ui", "key-sequence", "--help"], None),
    ("validation-ui-key-sequence-value", ["ui", "key-sequence", "999"], None),

    # ui key-combo
    ("help-ui-key-combo", ["ui", "key-combo", "--help"], None),
    ("error-ui-key-combo-missing-value", ["ui", "key-combo"], None),
    ("validation-ui-key-combo-value", ["ui", "key-combo", "--modifiers", "invalid", "--key", "4"], None),

    # ui button
    ("help-ui-button", ["ui", "button", "--help"], None),
    ("error-ui-button-missing-value", ["ui", "button"], None),
    ("validation-ui-button-value", ["ui", "button", "invalid-button"], None),

    # ui describe-all / describe-point
    ("help-ui-describe-all", ["ui", "describe-all", "--help"], None),
    ("help-ui-describe-point", ["ui", "describe-point", "--help"], None),
    ("error-ui-describe-point-missing-value", ["ui", "describe-point"], None),

    # ui slider
    ("help-ui-slider", ["ui", "slider", "--help"], None),
    ("error-ui-slider-missing-value", ["ui", "slider"], None),
    ("validation-ui-slider-value", ["ui", "slider", "--id", "x", "--value", "101"], None),

    # ui drag
    ("help-ui-drag", ["ui", "drag", "--help"], None),
    ("error-ui-drag-missing-value", ["ui", "drag"], None),
    ("validation-ui-drag-duration", ["ui", "drag", "1", "2", "3", "4", "--duration", "0"], None),

    # ui gesture
    ("help-ui-gesture", ["ui", "gesture", "--help"], None),
    ("error-ui-gesture-missing-value", ["ui", "gesture"], None),
    ("validation-ui-gesture-value", ["ui", "gesture", "invalid-gesture"], None),

    # ui touch
    ("help-ui-touch", ["ui", "touch", "--help"], None),
    ("error-ui-touch-missing-value", ["ui", "touch"], None),
    ("validation-ui-touch-mode", ["ui", "touch", "1", "2"], None),

    # Unsupported idb commands -> xcrun simctl pointer
    ("unsupported-install", ["install", "/nonexistent.app"], None),
    ("unsupported-launch", ["launch", "com.example.app"], None),
    ("unsupported-boot", ["boot", "SOME-UDID"], None),
    ("unsupported-connect", ["connect", "host", "1234"], None),
    ("unsupported-log", ["log"], None),
]


def record(binary: str, cases_dir: str) -> None:
    os.makedirs(cases_dir, exist_ok=True)
    for name, argv, stdin in CASES:
        case_dir = os.path.join(cases_dir, name)
        os.makedirs(case_dir, exist_ok=True)
        result = subprocess.run(
            [binary] + argv,
            input=stdin if stdin is not None else b"",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        with open(os.path.join(case_dir, "argv.txt"), "w") as f:
            f.write(" ".join(["taptaptap"] + argv) + "\n")
        with open(os.path.join(case_dir, "stdout.txt"), "wb") as f:
            f.write(result.stdout)
        with open(os.path.join(case_dir, "stderr.txt"), "wb") as f:
            f.write(result.stderr)
        with open(os.path.join(case_dir, "exit-code.txt"), "w") as f:
            f.write(str(result.returncode) + "\n")
        if stdin is not None:
            with open(os.path.join(case_dir, "stdin.txt"), "wb") as f:
                f.write(stdin)
        print(f"recorded {name}: exit={result.returncode}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    record(sys.argv[1], sys.argv[2])
