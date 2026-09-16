import Testing
@testable import TapTapTapSimulator

@Suite("Swipe event composition")
struct SwipeEventTests {
    private func touchPoints(_ event: FBSimulatorHIDEvent) -> [(Double, Double)] {
        switch event {
        case let .touch(_, x, y): return [(x, y)]
        case let .composite(events): return events.flatMap(touchPoints)
        default: return []
        }
    }

    @Test("A swipe shorter than delta still produces finite points (NOTE N6)")
    func shortSwipeIsFinite() {
        let event = FBSimulatorHIDEvent.swipe(10, yStart: 10, xEnd: 12, yEnd: 10, delta: 50, duration: 0.2)
        let points = touchPoints(event)
        #expect(!points.isEmpty)
        #expect(points.allSatisfy { $0.0.isFinite && $0.1.isFinite })
        #expect(points.last! == (12, 10))
    }

    @Test("A long swipe is split into distance / delta steps")
    func longSwipeSteps() {
        let event = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1)
        // 11 step points (0...10), one extra down at the end, one up.
        #expect(touchPoints(event).count == 13)
    }
}
