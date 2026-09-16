import Darwin
import Foundation
import Testing
@testable import TapTapTapCLI

/// taptaptap 3d NOTE N7: peer authentication before the handshake, finite coordinates only.
@Suite("HID Broker Hardening Tests")
struct HIDBrokerHardeningTests {
    @Test("A same-user socket peer is accepted; a non-socket descriptor is not")
    func sameUserPeer() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]); close(descriptors[1]) }
        #expect(HIDBroker.isSameUserPeer(descriptors[0]))

        var pipeDescriptors: [Int32] = [0, 0]
        #expect(pipe(&pipeDescriptors) == 0)
        defer { close(pipeDescriptors[0]); close(pipeDescriptors[1]) }
        #expect(!HIDBroker.isSameUserPeer(pipeDescriptors[0]))
    }

    @Test("Touch coordinates must be present and finite")
    func finiteCoordinates() throws {
        #expect(try HIDBroker.touchCoordinates(.touch(.down, x: 1, y: 2)) == (x: 1, y: 2))
        for primitive in [
            HIDBrokerPrimitive.touch(.down, x: .nan, y: 2),
            .touch(.up, x: 1, y: .infinity),
            HIDBrokerPrimitive(kind: .down, x: nil, y: 1, duration: nil),
        ] {
            #expect(throws: CLIError.self) { try HIDBroker.touchCoordinates(primitive) }
        }
    }

    @Test("Coordinates that overflow to infinity in JSON are rejected")
    func overflowingJSONCoordinates() throws {
        let data = Data(#"{"kind":"down","x":1e400,"y":1}"#.utf8)
        guard let primitive = try? JSONDecoder().decode(HIDBrokerPrimitive.self, from: data) else {
            return // The decoder refusing the value is also safe.
        }
        #expect(throws: CLIError.self) { try HIDBroker.touchCoordinates(primitive) }
    }
}
