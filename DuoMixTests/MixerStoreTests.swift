import XCTest
@testable import DuoMix

@MainActor
final class MixerStoreTests: XCTestCase {
    func testDemoAndLiveCommandsStayInTheirSession() throws {
        let spy = SpyDesk()
        let store = makeStore { _, _ in spy }
        XCTAssertEqual(store.channels.count, 32)
        store.select(2)
        store.setLevel(0.86, channel: 2)
        XCTAssertEqual(store.selected?.level, 0.86)
        store.host = "127.0.0.1"
        store.connect()
        XCTAssertEqual(store.status, .connecting)
        XCTAssertTrue(store.channels.isEmpty)
        store.setMute(true, channel: 2)
        XCTAssertTrue(spy.commands.isEmpty)

        spy.emitSnapshot()
        XCTAssertEqual(store.status, .live)
        XCTAssertEqual(store.selected?.level, 0.4)
        store.setLevel(0.3, channel: 2)
        XCTAssertEqual(spy.commands, ["level 2 0.3"])
        XCTAssertTrue(store.hasPendingWrites)
        XCTAssertEqual(store.selected?.level, 0.3)
        spy.onEvent?(.level(channel: 2, value: 0.3))
        XCTAssertFalse(store.hasPendingWrites)
        XCTAssertEqual(store.selected?.level, 0.3)
        store.setMute(true, channel: 2)
        spy.onEvent?(.mute(channel: 2, muted: true))
        XCTAssertEqual(store.selected?.isMuted, true)
        let delayedCallback = try XCTUnwrap(spy.onEvent)
        store.useDemo()
        delayedCallback(.name(channel: 2, name: "Stale update"))
        XCTAssertEqual(store.selected?.name, "Snare")
        XCTAssertTrue(spy.stopped)
    }

    func testWakeReadsFreshStateWithoutReplayingCommands() {
        let first = SpyDesk(), second = SpyDesk()
        var drivers = [first, second]
        let store = makeStore { _, _ in drivers.removeFirst() }
        store.host = "desk.local"
        store.connect()
        first.emitSnapshot()
        store.setLevel(0.5, channel: 2)
        store.suspend()
        XCTAssertTrue(first.stopped)
        XCTAssertFalse(store.canMix)
        store.resume()
        XCTAssertEqual(store.status, .connecting)
        store.setLevel(0.9, channel: 2)
        second.emitSnapshot()
        XCTAssertEqual(store.channels.first?.level, 0.4)
        XCTAssertTrue(second.commands.isEmpty)
    }

    func testLostSessionReconnectsFromNewSnapshot() async throws {
        let first = SpyDesk(), second = SpyDesk()
        let reopened = expectation(description: "Replacement connection")
        second.onStart = { reopened.fulfill() }
        var drivers = [first, second]
        let store = makeStore { _, _ in drivers.removeFirst() }
        store.host = "desk.local"
        store.connect()
        first.emitSnapshot()
        first.onEvent?(.failure("Lost connection."))
        store.setMute(true, channel: 2)
        XCTAssertFalse(store.canMix)
        await fulfillment(of: [reopened], timeout: 4)
        XCTAssertEqual(store.status, .connecting)
        second.emitSnapshot()
        XCTAssertEqual(store.status, .live)
        XCTAssertTrue(first.commands.isEmpty && second.commands.isEmpty)
    }

    func testInvalidEndpointAndUnreachableDeskStayOffline() {
        let desk = SpyDesk()
        let store = makeStore { _, _ in desk }
        store.host = "https://desk.local"
        store.connect()
        XCTAssertFalse(store.canMix)
        XCTAssertFalse(desk.started)
        store.host = "desk.local"
        store.port = "0"
        store.connect()
        XCTAssertFalse(desk.started)
        store.port = "53000"
        store.connect()
        XCTAssertTrue(desk.started)
        desk.onEvent?(.failure("Desk unavailable"))
        XCTAssertEqual(store.status, .offline("Desk unavailable"))
        XCTAssertTrue(store.channels.isEmpty)
    }

    func testSilentDeskReconcilesWithFreshSnapshotWithoutRepeatingWrite() async {
        let first = SpyDesk(), second = SpyDesk()
        let refresh = expectation(description: "Read back the silent desk")
        second.onStart = { refresh.fulfill() }
        var drivers = [first, second]
        let store = makeStore { _, _ in drivers.removeFirst() }
        store.host = "desk.local"
        store.connect()
        first.emitSnapshot()
        store.setLevel(0.65, channel: 2)
        first.onEvent?(.level(channel: 2, value: 0.42))
        XCTAssertTrue(store.hasPendingWrites)
        XCTAssertEqual(store.channels.first?.level, 0.65)
        await fulfillment(of: [refresh], timeout: 5)
        second.emitSnapshot()
        XCTAssertFalse(store.hasPendingWrites)
        XCTAssertEqual(store.channels.first?.level, 0.4)
        XCTAssertEqual(first.commands, ["level 2 0.65"])
        XCTAssertTrue(second.commands.isEmpty)
    }

    private func makeStore(factory: @escaping @MainActor (String, UInt16) -> MixerDriver) -> MixerStore {
        MixerStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, makeDriver: factory)
    }
}

@MainActor
private final class SpyDesk: MixerDriver {
    var onEvent: ((MixerEvent) -> Void)?
    var onStart: (() -> Void)?
    var started = false
    var stopped = false
    var commands: [String] = []
    func start() { started = true; onStart?() }
    func stop() { stopped = true }
    func emitSnapshot() {
        onEvent?(.snapshot([MixerChannel(id: 2, name: "Desk input", level: 0.4, isMuted: false)]))
    }
    func setLevel(_ value: Double, channel: Int) { commands.append("level \(channel) \(value)") }
    func setMute(_ muted: Bool, channel: Int) { commands.append("mute \(channel) \(muted)") }
}
