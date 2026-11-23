import Network
import XCTest

final class LiveSessionTests: XCTestCase {
    func testConnectMixAndDisconnectFromDesk() throws {
        continueAfterFailure = false
        let ready = expectation(description: "Loopback desk is listening")
        let unmute = expectation(description: "Desk receives the UI's unmute command")
        let disconnected = expectation(description: "App closes its TCP session")
        let queue = DispatchQueue(label: "DuoMixUITests.desk")
        let listener = try DeskWire.listener()
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
        XCTAssertTrue(app.staticTexts["main-mix-title"].exists)
        let fader = app.descendants(matching: .any).matching(identifier: "fader-1").firstMatch
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
        XCTAssertTrue(app.staticTexts["demo-desk-title"].waitForExistence(timeout: 5))
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }
}
