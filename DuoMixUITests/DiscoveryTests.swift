import Network
import XCTest

final class DiscoveryTests: XCTestCase {
    func testScanThenConnectToSelectedMixer() throws {
        continueAfterFailure = false
        let queue = DispatchQueue(label: "DuoMixUITests.discoveryDesk")
        let listener = try DeskWire.listener()
        var sessions = [NWConnection]()
        defer {
            listener.cancel()
            queue.sync { sessions.forEach { $0.cancel() } }
        }
        let ready = expectation(description: "Loopback desk is listening")
        let probeClosed = expectation(description: "Scan released its verified connection")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case let .failed(error) = state { XCTFail("Desk listener failed: \(error)") }
        }
        listener.newConnectionHandler = { peer in
            let isProbe = sessions.isEmpty
            sessions.append(peer)
            peer.start(queue: queue)
            DeskWire.receive(from: peer, onClose: {
                if isProbe { probeClosed.fulfill() }
            }) { type, body in
                switch type {
                case "JM":
                    let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body.dropFirst(4)) as? [String: Any])
                    XCTAssertEqual(request["id"] as? String, "Subscribe")
                    DeskWire.sendInitialState(to: peer)
                case "KA", "UM":
                    XCTAssertFalse(isProbe, "Only the selected session needs keepalive or meters")
                default:
                    XCTFail("Unexpected control command during mixer discovery or selection: \(type)")
                }
                return true
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)

        let app = XCUIApplication()
        let port = try XCTUnwrap(listener.port)
        app.launchEnvironment["DUOMIX_TEST_SCAN_PORT"] = String(port.rawValue)
        app.launch()
        let connection = app.buttons["connections"]
        connection.tap()
        app.buttons["scan-mixers"].tap()
        let result = app.buttons["discovered-127.0.0.1"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        wait(for: [probeClosed], timeout: 5)
        XCTAssertEqual(queue.sync { sessions.count }, 1, "Finding a mixer must wait for the user's selection")

        result.tap()
        let live = NSPredicate(format: "label == %@", "Mixer connection, Live")
        wait(for: [XCTNSPredicateExpectation(predicate: live, object: connection)], timeout: 10)
        XCTAssertEqual(queue.sync { sessions.count }, 2)
        XCTAssertEqual(app.buttons["mute-1"].value as? String, "On")
        let fader = app.descendants(matching: .any).matching(identifier: "fader-1").firstMatch
        XCTAssertEqual(fader.value as? String, "25%")
        connection.tap()
        app.buttons["Disconnect"].tap()
        app.buttons["use-demo"].tap()
    }
}
