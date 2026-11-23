import Combine
import XCTest
@testable import DuoMix

@MainActor
final class MeterStateTests: XCTestCase {
    func testLiveMetersAreSeparateFromFadersAndScopedToTheSession() throws {
        let desk = MeterDesk()
        let store = makeStore(desk)
        store.host = "desk.local"
        store.connect()
        desk.onEvent?(.meters([1: -8]))
        XCTAssertTrue(store.meterLevels.isEmpty)
        desk.synchronize()
        let priorState = store.channels

        var surfaceChanges = 0
        let observer = store.objectWillChange.sink { surfaceChanges += 1 }
        desk.onEvent?(.meters([1: -.infinity, 2: -4.5, 3: .nan, 4: .infinity, 99: 0]))
        XCTAssertEqual(store.meterLevels, [1: -.infinity, 2: -4.5])
        desk.onEvent?(.meters([2: -2]))
        XCTAssertEqual(store.meterLevels, [2: -2])
        XCTAssertEqual(store.channels, priorState)
        XCTAssertEqual(surfaceChanges, 0)
        observer.cancel()

        let previousSession = try XCTUnwrap(desk.onEvent)
        store.disconnect()
        XCTAssertTrue(store.meterLevels.isEmpty)
        previousSession(.meters([1: -3]))
        XCTAssertTrue(store.meterLevels.isEmpty)
    }

    func testSilenceExpiresWhenTheDeskStopsSending() async {
        let desk = MeterDesk()
        let store = makeStore(desk)
        store.host = "desk.local"
        store.connect()
        desk.synchronize()
        desk.onEvent?(.meters([1: -.infinity]))
        let expired = expectation(description: "A stalled meter becomes unavailable")
        let observer = store.meters.$levels.dropFirst().filter(\.isEmpty).first().sink { _ in expired.fulfill() }
        await fulfillment(of: [expired], timeout: 5)
        XCTAssertTrue(store.meterLevels.isEmpty)
        XCTAssertEqual(store.status, .live)
        observer.cancel()
    }

    func testSimulatedInputKeepsMovingWithMutedFaderAndPausesInBackground() async throws {
        let store = makeStore(MeterDesk())
        store.select(2)
        store.setLevel(0, channel: 2)
        store.setMute(true, channel: 2)
        let signalChanges = expectation(description: "Two distinct input signals on muted channel")
        let liveSignal = store.meters.$levels.compactMap { $0[2] }.removeDuplicates().prefix(2)
        signalChanges.expectedFulfillmentCount = 2
        let observer = liveSignal.sink { value in
            XCTAssertTrue(value.isFinite)
            signalChanges.fulfill()
        }
        await fulfillment(of: [signalChanges], timeout: 4)
        observer.cancel()
        XCTAssertEqual(store.meterLevels[32], -.infinity)

        store.suspend()
        XCTAssertTrue(store.meterLevels.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(store.meterLevels.isEmpty)
        store.resume()
        XCTAssertEqual(store.selectedID, 2)
        XCTAssertEqual(store.selected?.level, 0)
        XCTAssertEqual(store.selected?.isMuted, true)
        let resumed = expectation(description: "Demo meter resumes")
        let resumedObserver = store.meters.$levels.compactMap { $0[2] }.first().sink { _ in resumed.fulfill() }
        await fulfillment(of: [resumed], timeout: 4)
        resumedObserver.cancel()

        store.host = "desk.local"
        store.connect()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(store.meterLevels.isEmpty)
    }

    private func makeStore(_ desk: MeterDesk) -> MixerStore {
        MixerStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, makeDriver: { _, _ in desk })
    }
}

@MainActor
private final class MeterDesk: MixerDriver {
    var onEvent: ((MixerEvent) -> Void)?
    func start() {}
    func stop() {}
    func setLevel(_ value: Double, channel: Int) {}
    func setMute(_ muted: Bool, channel: Int) {}
    func synchronize() {
        onEvent?(.snapshot((1...4).map { MixerChannel(id: $0, name: "Input \($0)", level: 0.35, isMuted: false) }))
    }
}
