import Testing
import Foundation
@testable import TapTapTapCLI

@Suite("Drag Command Surface Tests")
struct DragCommandSurfaceTests {
    @Test("Drag help includes coordinate and timing options")
    func dragHelpIncludesCoordinateAndTimingOptions() async throws {
        let result = try await TestHelpers.runAxeCommand("ui drag --help")

        #expect(result.output.contains("<x-start>") || result.output.contains("x-start"))
        #expect(result.output.contains("--duration"))
        #expect(result.output.contains("--steps"))
    }

    @Test("Invalid drag coordinates fail validation")
    func invalidDragCoordinatesFailValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "ui drag 100 100 100 100 --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("Start and end points must be different."))
    }

    @Test("Too many drag steps fails validation")
    func tooManyDragStepsFailsValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "ui drag 100 100 100 200 --steps 1001 --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("Steps must be between 1 and 1000."))
    }

    @Test("Composite drag plan includes move points between touch down and touch up")
    @MainActor
    func compositeDragPlanIncludesMovePoints() throws {
        let movePoints = try HIDInteractor.compositeDragMovePoints(
            from: (x: 100, y: 200),
            to: (x: 300, y: 600),
            steps: 4
        )

        #expect(movePoints.count == 4)
        #expect(movePoints.first?.x == 150)
        #expect(movePoints.first?.y == 300)
        #expect(movePoints.last?.x == 300)
        #expect(movePoints.last?.y == 600)
        #expect(movePoints.contains { point in
            point.x > 100 && point.x < 300 && point.y > 200 && point.y < 600
        })
    }
}
