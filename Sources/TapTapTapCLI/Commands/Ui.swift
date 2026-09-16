import TapTapTapArguments

/// idb: `CommandGroup(name="ui", ...)` (main.py:259-274) — HID input, accessibility, and (per the
/// charter/team-lead's decisions) taptaptap's own extras, all re-expressed in idb's grammar.
/// A command with subcommands and no run() of its own prints its help (TapTapTapArguments
/// default), matching `taptaptap ui` / `taptaptap ui --help`.
struct Ui: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "UI interactions on target",
        subcommands: [
            DescribeAll.self,
            DescribePoint.self,
            Tap.self,
            MultiTap.self,
            Pinch.self,
            Button.self,
            Text.self,
            Key.self,
            KeySequence.self,
            Swipe.self,
            Slider.self,
            Drag.self,
            Gesture.self,
            Touch.self,
            KeyCombo.self
        ]
    )
}
