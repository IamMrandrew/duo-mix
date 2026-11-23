import Network
import XCTest

final class LiveSessionTests: XCTestCase {
    func testConnectMixAndDisconnectFromDesk() throws {
        continueAfterFailure = false
        let ready = expectation(description: "Loopback desk is listening")
        let registered = expectation(description: "App registers its UDP meter port")
        let unmute = expectation(description: "Desk receives the UI's unmute command")
        let disconnected = expectation(description: "App closes its TCP session")
        let queue = DispatchQueue(label: "DuoMixUITests.desk")
        let listener = try DeskWire.listener()
        var meterPort: NWEndpoint.Port?
        defer { listener.cancel() }
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case let .failed(error) = state { XCTFail("Desk listener failed: \(error)") }
        }
        listener.newConnectionHandler = { peer in
            peer.start(queue: queue)
            DeskWire.receive(from: peer, onClose: { disconnected.fulfill() }) { type, body in
                switch type {
                case "JM":
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body.dropFirst(4)) as? [String: Any])
                    if json["id"] as? String == "Subscribe" { DeskWire.sendInitialState(to: peer) }
                case "UM":
                    guard body.count == 2 else { XCTFail("Invalid meter registration"); return false }
                    meterPort = NWEndpoint.Port(rawValue: UInt16(body[0]) | (UInt16(body[1]) << 8))
                    registered.fulfill()
                case "PV":
                    let expected = Data("line/ch1/mute".utf8) + [0, 0, 0, 0, 0, 0, 0]
                    XCTAssertEqual(body, expected)
                    unmute.fulfill()
                    peer.send(content: DeskWire.frame("PV", expected), completion: .contentProcessed { error in
                        if let error { XCTFail("Sending desk confirmation failed: \(error)") }
                    })
                default: break
                }
                return true
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port).rawValue

        let app = XCUIApplication()
        app.launch()
        let connections = app.buttons["connections"]
        connections.tap()
        replace(app.textFields["mixer-host"], with: "127.0.0.1")
        replace(app.textFields["mixer-port"], with: String(port))
        let connect = app.buttons["connect-mixer"]
        if !connect.isHittable {
            // The number pad can cover the form's last row in a compact window.
            app.buttons["Done"].tap()
            connections.tap()
        }
        connect.tap()

        let live = NSPredicate(format: "label == %@", "Mixer connection, Live")
        wait(for: [XCTNSPredicateExpectation(predicate: live, object: connections)], timeout: 10)
        wait(for: [registered], timeout: 5)
        let meter = app.descendants(matching: .any).matching(identifier: "meter-1").firstMatch
        XCTAssertEqual(meter.label, "Kick input meter")
        XCTAssertEqual(meter.value as? String, "Unavailable")
        let destination = try XCTUnwrap(queue.sync { meterPort })
        // One input group. Raw linear magnitude 32768/65535 is approximately −6 dBFS.
        let sample = Data([0x55, 0x43, 0, 1, UInt8(truncatingIfNeeded: port), UInt8(port >> 8),
                           0x4d, 0x53, 0x65, 0, 0x6a, 0, 0x6c, 0x65, 0x76, 0x6c,
                           0, 0, 1, 0, 0, 0x80, 1, 0, 0, 0, 0, 1, 0])
        let feed = try DeskWire.meterStream(from: XCTUnwrap(listener.port), to: destination, sample: sample, queue: queue)
        defer { feed.cancel() }
        let signal = NSPredicate(format: "value == %@", "Approximately −6 decibels full scale")
        wait(for: [XCTNSPredicateExpectation(predicate: signal, object: meter)], timeout: 8)
        let fader = app.descendants(matching: .any).matching(identifier: "fader-1").firstMatch
        XCTAssertEqual(fader.label, "Kick fader position")
        XCTAssertEqual(fader.value as? String, "25%")
        let mute = app.buttons["mute-1"]
        XCTAssertEqual(mute.value as? String, "On")
        mute.tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Off"), object: mute)
        wait(for: [unmute, off], timeout: 5)

        connections.tap()
        app.buttons["Disconnect"].tap()
        wait(for: [disconnected], timeout: 5)
        app.buttons["use-demo"].tap()
        let demo = NSPredicate(format: "label == %@", "Mixer connection, Demo")
        wait(for: [XCTNSPredicateExpectation(predicate: demo, object: connections)], timeout: 5)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        let current = field.value as? String ?? ""
        guard current != value else { return }
        // Both fields are trailing-aligned. Tap after the final character, then erase the
        // previous endpoint. Command-A can leave a caret in the URL keyboard on iPhone.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "Check the entered endpoint before connecting")
    }
}
