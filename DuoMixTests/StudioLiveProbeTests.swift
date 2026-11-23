import Network
import XCTest
@testable import DuoMix

final class StudioLiveProbeTests: XCTestCase {
    func testAcceptsMixerSnapshotAndClosesAfterSubscriptionOnly() async throws {
        let closed = expectation(description: "Probe closed the read-only session")
        let listener = try await listen { peer in
            var requests = 0
            DeskWire.receive(from: peer, onClose: {
                XCTAssertEqual(requests, 1)
                closed.fulfill()
            }) { kind, body in
                requests += 1
                XCTAssertEqual(kind, "JM")
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body.dropFirst(4)) as? [String: Any])
                XCTAssertEqual(fields["id"] as? String, "Subscribe")
                XCTAssertEqual(fields["clientIdentifier"] as? String, "test-installation")
                DeskWire.sendInitialState(to: peer)
                return true
            }
        }
        defer { listener.cancel() }
        let found = try await identify(listener)
        XCTAssertEqual(found, "StudioLive")
        await fulfillment(of: [closed], timeout: 3)
    }

    func testReportsDeskNicknameThenModelWhenNicknameIsBlank() async throws {
        // Independent compressed Synchronize fixtures. Both name fields are at
        // children.global.values, matching a recorded StudioLive 16R snapshot.
        let fixtures = [
            ("eJxNjTsKAjEYBoMui6yFeINcQT2AnVgIFmnsJCY/5oM8ICbBNeTuLtrsVANTTMUCWmAtRq9MDB4fwkoZWB3JV/RPGx7STlKkzfSqGBzeFO9eOhLYci6kVynLOPLT9cw5Bk0Fiv59I1LWCBcU4oe9uLWGzsJTnT+Wyuxmg74Emx3pI2MMncuJ9GSs/fgCq7U9hA==", "Sanctuary FOH"),
            ("eJxNjDEOAiEUBVE3G4OFV/AK6gG8gB2NnUH+j7zkA8nuQlTC3d1os1PNNFOxBhnszDs6P6SID2PrPIQGjhX9U9LDyizFSuaxQge8eLhHG9hgpaGJCxz/e2+mTEhXFD6cT+bWGjpB5Lp8bpw/LoZ9SZID00UphS7kiWk21X58ARCCOEc=", "StudioLive 32SX")
        ]
        for (base64, name) in fixtures {
            let state = try XCTUnwrap(Data(base64Encoded: base64))
            let reply = Data(#"{"id":"SubscriptionReply"}"#.utf8)
            let frames = DeskWire.frame("ZB", Data([UInt8(state.count), 0, 0, 0]) + state)
                + DeskWire.frame("JM", Data([UInt8(reply.count), 0, 0, 0]) + reply)
            let listener = try await listen { peer in
                DeskWire.receive(from: peer, onClose: {}) { _, _ in
                    peer.send(content: frames, completion: .contentProcessed { error in
                        XCTAssertNil(error)
                    })
                    return true
                }
            }
            defer { listener.cancel() }
            let found = try await identify(listener)
            XCTAssertEqual(found, name)
        }
    }

    func testRejectsUnrelatedTCPService() async throws {
        let listener = try await listen { peer in
            peer.send(content: Data("HTTP/1.1 400 Bad Request\r\n\r\n".utf8),
                      completion: .contentProcessed { _ in peer.cancel() })
        }
        defer { listener.cancel() }
        let found = try await identify(listener)
        XCTAssertNil(found)
    }

    func testCancellingSilentPeerClosesSocket() async throws {
        let subscribed = expectation(description: "Probe subscribed")
        let closed = expectation(description: "Cancelled connection closed")
        let listener = try await listen { peer in
            DeskWire.receive(from: peer, onClose: { closed.fulfill() }) { _, _ in
                subscribed.fulfill()
                return true
            }
        }
        defer { listener.cancel() }
        let probe = Task { try await self.identify(listener) }
        await fulfillment(of: [subscribed], timeout: 3)
        probe.cancel()
        do {
            _ = try await probe.value
            XCTFail("A cancelled probe must throw")
        } catch is CancellationError {}
        await fulfillment(of: [closed], timeout: 3)
    }

    private func identify(_ listener: NWListener) async throws -> String? {
        let port = try XCTUnwrap(listener.port).rawValue
        return try await StudioLiveProbe.identify(host: "127.0.0.1", port: port,
                                                  interface: nil, clientID: "test-installation")
    }

    private func listen(_ handle: @escaping (NWConnection) -> Void) async throws -> NWListener {
        let listener = try DeskWire.listener()
        let ready = expectation(description: "Loopback TCP listener ready")
        let queue = DispatchQueue(label: "DuoMixTests.probe")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { peer in
            peer.start(queue: queue)
            handle(peer)
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        return listener
    }
}
