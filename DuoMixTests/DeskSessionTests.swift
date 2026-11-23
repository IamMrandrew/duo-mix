import Network
import XCTest
@testable import DuoMix

final class DeskSessionTests: XCTestCase {
    @MainActor
    func testRemoteSessionOnLoopback() async throws {
        let listening = expectation(description: "Loopback listener ready")
        let synchronized = expectation(description: "Initial mixer state delivered")
        let remoteLevel = expectation(description: "Console fader move delivered")
        let remoteMute = expectation(description: "Console mute delivered")
        let writes = expectation(description: "Desk received both requested changes")
        let lostConnection = expectation(description: "Desk disconnect reported")
        let listener = try DeskWire.listener()
        defer { listener.cancel() }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: listening.fulfill()
            case let .failed(error): XCTFail("Loopback listener failed: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { peer in
            peer.start(queue: .main)
            var pending = Set(["line/ch1/volume", "line/ch1/mute"])
            var subscribed = false
            DeskWire.receive(from: peer) { type, body in
                switch type {
                case "JM":
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body.dropFirst(4)) as? [String: Any])
                    guard json["id"] as? String == "Subscribe" else { return true }
                    XCTAssertFalse(subscribed)
                    subscribed = true
                    DeskWire.sendInitialState(to: peer)
                case "PV":
                    XCTAssertTrue(subscribed)
                    let end = try XCTUnwrap(body.firstIndex(of: 0))
                    let path = String(decoding: body[..<end], as: UTF8.self)
                    XCTAssertNotNil(pending.remove(path), "Unexpected desk parameter \(path)")
                    let expected: [UInt8] = path == "line/ch1/volume"
                        ? [0, 0, 0, 0, 0, 0x40, 0x3f]  // Float32 0.75
                        : [0, 0, 0, 0, 0, 0, 0]        // Float32 0.0
                    XCTAssertEqual(Array(body[end...]), expected)
                    if pending.isEmpty {
                        writes.fulfill()
                        peer.cancel()
                        return false
                    }
                default: break // Greeting and heartbeat do not change the desk.
                }
                return true
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)

        let port = try XCTUnwrap(listener.port).rawValue
        let driver = PreSonusDriver(host: "127.0.0.1", port: port)
        defer { driver.stop() }
        driver.onEvent = { event in
            switch event {
            case let .snapshot(channels):
                XCTAssertEqual(channels.count, 1)
                XCTAssertEqual(channels.first?.id, 1)
                XCTAssertEqual(channels.first?.name, "Kick")
                XCTAssertEqual(channels.first?.level, 0.5)
                XCTAssertEqual(channels.first?.isMuted, false)
                synchronized.fulfill()
            case let .level(channel, value):
                XCTAssertEqual(channel, 1)
                XCTAssertEqual(value, 0.25)
                remoteLevel.fulfill()
            case let .mute(channel, muted):
                XCTAssertEqual(channel, 1)
                XCTAssertTrue(muted)
                remoteMute.fulfill()
            case .failure:
                lostConnection.fulfill()
            default: break
            }
        }
        driver.start()
        await fulfillment(of: [synchronized, remoteLevel, remoteMute], timeout: 5, enforceOrder: true)
        driver.setLevel(0.75, channel: 1)
        driver.setMute(false, channel: 1)
        await fulfillment(of: [writes, lostConnection], timeout: 5, enforceOrder: true)
    }
}
