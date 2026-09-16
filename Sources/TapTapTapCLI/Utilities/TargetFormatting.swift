import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `human_format_target_info`/`json_data_target_info` (idb/common/format.py:215-240) — shared
/// by `list-targets` and `describe`. taptaptap has no companion process, so the trailing
/// human-format field is always "No Companion Connected", which is exactly what idb itself prints
/// for an unconnected target (docs/IDB-COMPAT.md §2).
enum TargetFormatting {
    static func humanLine(_ simulator: FBSimulator) -> String {
        let state = FBiOSTargetStateStringFromState(simulator.state).rawValue
        let osVersion = simulator.osVersion.name.rawValue
        let architecture = simulator.configuration.device.deviceArchitecture.rawValue
        return "\(simulator.name) | \(simulator.udid) | \(state) | simulator | \(osVersion) | \(architecture) | No Companion Connected"
    }

    static func jsonLine(_ simulator: FBSimulator) -> String {
        let state = FBiOSTargetStateStringFromState(simulator.state).rawValue
        let payload: [String: Any] = [
            "name": simulator.name,
            "udid": simulator.udid,
            "state": state,
            "type": "simulator",
            "os_version": simulator.osVersion.name.rawValue,
            "architecture": simulator.configuration.device.deviceArchitecture.rawValue
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
