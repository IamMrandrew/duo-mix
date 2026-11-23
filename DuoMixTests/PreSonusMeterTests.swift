import Network
import XCTest
@testable import DuoMix

final class PreSonusMeterTests: XCTestCase {
    // Independent packet: the first slot belongs to the main bus. Slots 1 and
    // 2 belong to input group zero. UDP bytes 4–5 advertise desk port 53000.
    private static let sample = Data([
        0x55, 0x43, 0, 1, 0x08, 0xcf, 0x4d, 0x53, 0x65, 0, 0x6a, 0,
        0x6c, 0x65, 0x76, 0x6c, 0, 0, 3, 0,
        0xff, 0xff, 0x00, 0x80, 0x00, 0x00, 2,
        7, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0
    ])

    func testInputTapAndSilentChannel() throws {
        let levels = try XCTUnwrap(PreSonusMeter.inputLevels(Self.sample))
        XCTAssertEqual(levels.count, 2)
        XCTAssertEqual(try XCTUnwrap(levels[1]), -6.02047, accuracy: 0.0001)
        XCTAssertEqual(levels[2], -.infinity)
        XCTAssertEqual(PreSonusWire.meterRegistration(port: 0xfa15),
                       Data([0x55, 0x43, 0, 1, 8, 0, 0x55, 0x4d, 0, 0, 0x65, 0, 0x15, 0xfa]))
    }

    func testIgnoresOtherStreamsAndIncompleteVectors() {
        var faders = Self.sample
        faders.replaceSubrange(12..<16, with: "fdrs".utf8)
        XCTAssertNil(PreSonusMeter.inputLevels(faders))
        XCTAssertNil(PreSonusMeter.inputLevels(Self.sample.dropLast()))
        var outsideVector = Self.sample
        outsideVector[outsideVector.count - 2] = 4
        XCTAssertNil(PreSonusMeter.inputLevels(outsideVector))
    }

    @MainActor
    func testDriverRegistersUDPPortAndReceivesMetersFromItsConsole() async throws {
        let listener = try DeskWire.listener()
        var feed: DispatchSourceTimer?
        let ready = expectation(description: "Desk TCP listener")
        let synchronized = expectation(description: "Driver synchronized channel state")
        let registered = expectation(description: "Desk received UM with the driver's UDP port")
        let reading = expectation(description: "Driver received the synchronized desk's input meter")
        defer {
            feed?.cancel()
            listener.cancel()
        }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { peer in
            peer.start(queue: .main)
            DeskWire.receive(from: peer, onClose: {}) { type, body in
                if type == "JM" { DeskWire.sendInitialState(to: peer) }
                if type == "UM" {
                    XCTAssertEqual(body.count, 2)
                    guard body.count == 2 else { return false }
                    let value = UInt16(body[0]) | UInt16(body[1]) << 8
                    let destination = try XCTUnwrap(NWEndpoint.Port(rawValue: value))
                    let port = try XCTUnwrap(listener.port)
                    Task { @MainActor in
                        registered.fulfill()
                        do { feed = try DeskWire.meterStream(from: port, to: destination, sample: Self.sample, queue: .main) }
                        catch { XCTFail("Could not start the meter source: \(error)") }
                    }
                }
                return true
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        let driver = PreSonusDriver(host: "127.0.0.1", port: try XCTUnwrap(listener.port).rawValue)
        defer {
            driver.onEvent = nil
            driver.stop()
        }
        driver.onEvent = { event in
            if case .snapshot = event { synchronized.fulfill() }
            if case let .meters(levels) = event, !levels.isEmpty {
                XCTAssertEqual(levels.count, 1, "Only channel 1 is in this desk's snapshot.")
                XCTAssertEqual(levels[1] ?? 0, -6.02047, accuracy: 0.0001)
                driver.onEvent = nil
                feed?.cancel()
                reading.fulfill()
            }
            if case let .failure(message) = event { XCTFail(message) }
        }
        driver.start()
        await fulfillment(of: [synchronized, registered, reading], timeout: 12, enforceOrder: true)
    }
}
