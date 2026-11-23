import Combine
import Foundation

/// Only the meter views observe this object. Signal updates arrive more often than controls change.
@MainActor
final class MixerMeters: ObservableObject {
    @Published private(set) var levels: [Int: Double] = [:]
    private var deadline: ContinuousClock.Instant?
    private var expiry: Task<Void, Never>?

    fileprivate func replace(with frame: [Int: Double]) {
        guard !frame.isEmpty else { clear(); return }
        if levels != frame { levels = frame }
        deadline = .now.advanced(by: .milliseconds(1500))
        guard expiry == nil else { return }
        // One sleeper follows the latest deadline even while frames arrive at 10 Hz.
        expiry = Task { [weak self] in
            while let deadline = self?.deadline {
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard let self, let latest = self.deadline else { return }
                if latest <= .now { self.clear(); return }
            }
        }
    }

    fileprivate func clear() {
        deadline = nil
        expiry?.cancel()
        expiry = nil
        if !levels.isEmpty { levels = [:] }
    }

    deinit { expiry?.cancel() }
}

@MainActor
final class MixerStore: ObservableObject {
    @Published private(set) var channels: [MixerChannel] = []
    @Published private(set) var selectedID = 1
    @Published private(set) var status = MixerStatus.demo
    @Published var host: String
    @Published var port: String
    let meters = MixerMeters()

    var meterLevels: [Int: Double] { meters.levels }
    var selected: MixerChannel? { channels.first { $0.id == selectedID } }
    var canMix: Bool { !isSuspended && (status == .demo || status == .live) }

    private struct Endpoint {
        let host: String
        let port: UInt16
    }

    private enum Parameter: Hashable {
        case level(Int), mute(Int)
    }

    @Published private var pending: [Parameter: Double] = [:]
    var hasPendingWrites: Bool { !pending.isEmpty }
    private var readbackTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let makeDriver: @MainActor (String, UInt16) -> MixerDriver
    private var driver: MixerDriver?
    private var generation = UUID()
    private var endpoint: Endpoint?
    private var retryTask: Task<Void, Never>?
    private var retriesLeft = 0
    private var isSuspended = false

    init(defaults: UserDefaults = .standard,
         makeDriver: @escaping @MainActor (String, UInt16) -> MixerDriver = { PreSonusDriver(host: $0, port: $1) }) {
        self.defaults = defaults
        self.makeDriver = makeDriver
        host = defaults.string(forKey: "mixerHost") ?? ""
        port = defaults.string(forKey: "mixerPort") ?? "53000"
        useDemo()
    }

    func select(_ id: Int) {
        if channels.contains(where: { $0.id == id }) { selectedID = id }
    }

    func setLevel(_ value: Double, channel: Int) {
        guard canMix, value.isFinite, let index = channels.firstIndex(where: { $0.id == channel }) else { return }
        let target = min(1, max(0, value))
        if status == .live {
            expectReadback(.level(channel), value: target)
            channels[index].level = target
        }
        driver?.setLevel(target, channel: channel)
    }

    func setMute(_ muted: Bool, channel: Int) {
        guard canMix, let index = channels.firstIndex(where: { $0.id == channel }) else { return }
        if status == .live {
            expectReadback(.mute(channel), value: muted ? 1 : 0)
            channels[index].isMuted = muted
        }
        driver?.setMute(muted, channel: channel)
    }

    private func expectReadback(_ key: Parameter, value: Double) {
        pending[key] = value
        readbackTask?.cancel()
        readbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, self.hasPendingWrites else { return }
            // Some desks may only report another controller's writes. A fresh
            // subscription reads all values without replaying a local command.
            self.openEndpoint()
        }
    }

    private func accepts(_ key: Parameter, value: Double) -> Bool {
        guard let expected = pending[key] else { return true }
        // A prior drag sample may still be in flight on the ordered TCP stream.
        guard abs(expected - value) < 0.0001 else { return false }
        pending.removeValue(forKey: key)
        if pending.isEmpty { clearReadbacks() }
        return true
    }

    private func clearReadbacks() {
        readbackTask?.cancel()
        readbackTask = nil
        pending.removeAll()
    }

    func connect() {
        disconnect()
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !address.contains(where: { $0.isWhitespace }),
              !address.contains("/"), let number = UInt16(portText), number > 0 else {
            status = .offline("Enter the desk’s IP address or hostname and a port from 1 to 65535.")
            return
        }
        endpoint = Endpoint(host: address, port: number)
        openEndpoint()
    }

    func disconnect() {
        endpoint = nil
        retriesLeft = 0
        tearDown()
        status = .offline("Disconnected.")
    }

    func useDemo() {
        disconnect()
        status = .demo
        attach(DemoDriver())
    }

    func suspend() {
        isSuspended = true
        if status == .demo {
            driver?.stop()
            meters.clear()
            return
        }
        guard endpoint != nil else { return }
        tearDown()
        status = .offline("Connection paused.")
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if status == .demo { driver?.start() }
        else if endpoint != nil { openEndpoint() }
    }

    private func openEndpoint() {
        guard let endpoint, !isSuspended else { return }
        tearDown()
        status = .connecting
        attach(makeDriver(endpoint.host, endpoint.port))
    }

    private func attach(_ newDriver: MixerDriver) {
        driver = newDriver
        let session = generation
        newDriver.onEvent = { [weak self] event in
            guard let self, session == self.generation else { return }
            self.receive(event)
        }
        if !isSuspended { newDriver.start() }
    }

    private func tearDown() {
        meters.clear()
        clearReadbacks()
        retryTask?.cancel()
        retryTask = nil
        generation = UUID()
        driver?.onEvent = nil
        driver?.stop()
        driver = nil
        channels = []
    }

    private func receive(_ event: MixerEvent) {
        switch event {
        case .snapshot(let snapshot):
            meters.clear()
            clearReadbacks()
            channels = snapshot
            if selected == nil, let first = snapshot.first { selectedID = first.id }
            if let endpoint {
                defaults.set(endpoint.host, forKey: "mixerHost")
                defaults.set(String(endpoint.port), forKey: "mixerPort")
                status = .live
                retriesLeft = 3
            }
        case let .level(id, value):
            guard value.isFinite, (0...1).contains(value), accepts(.level(id), value: value) else { return }
            if let index = channels.firstIndex(where: { $0.id == id }), channels[index].level != value {
                channels[index].level = value
            }
        case let .mute(id, muted):
            guard accepts(.mute(id), value: muted ? 1 : 0) else { return }
            if let index = channels.firstIndex(where: { $0.id == id }) { channels[index].isMuted = muted }
        case let .name(id, name):
            if let index = channels.firstIndex(where: { $0.id == id }) { channels[index].name = name }
        case let .meters(frame):
            guard canMix else { return }
            var readings = [Int: Double](minimumCapacity: channels.count)
            for channel in channels {
                if let db = frame[channel.id], db.isFinite || db == -.infinity {
                    readings[channel.id] = db
                }
            }
            meters.replace(with: readings)
        case .failure(let message):
            tearDown()
            guard retriesLeft > 0, endpoint != nil, !isSuspended else {
                endpoint = nil
                status = .offline(message)
                return
            }
            let delay = 4 - retriesLeft
            retriesLeft -= 1
            status = .offline("\(message) Reconnecting…")
            retryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                self?.openEndpoint()
            }
        }
    }
}
