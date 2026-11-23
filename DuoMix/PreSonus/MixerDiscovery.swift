import Combine
import Foundation
import Network

enum StudioLiveScanError: LocalizedError {
    case noNetwork, localNetworkDenied

    var errorDescription: String? {
        switch self {
        case .noNetwork: "Join the mixer’s Wi-Fi or Ethernet network, then scan again."
        case .localNetworkDenied: "Allow Local Network access for Duo Mix in Settings, then scan again."
        }
    }
}

struct DiscoveredMixer: Identifiable {
    let name: String
    let host: String
    let port: UInt16
    var id: String { "\(host):\(port)" }
}

@MainActor
final class MixerDiscovery: ObservableObject {
    enum Phase: Equatable { case idle, scanning, stopped, finished, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mixers: [DiscoveredMixer] = []
    @Published private(set) var checked = 0
    @Published private(set) var total = 0
    private(set) var isPartial = false
    private var task: Task<Void, Never>?

    func start() {
        stop()
        mixers = []
        checked = 0
        total = 0
        isPartial = false
        phase = .scanning
        task = Task { [weak self] in await self?.scan() }
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = .stopped }
    }

    private func scan() async {
        do {
            try await scanLocalNetwork()
            try Task.checkCancellation()
            phase = .finished
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
        task = nil
    }

    private func scanLocalNetwork() async throws {
        #if DEBUG && targetEnvironment(simulator)
        // Route the UI test through the same protocol probe and picker as a real scan.
        if let raw = ProcessInfo.processInfo.environment["DUOMIX_TEST_SCAN_PORT"],
           let port = UInt16(raw), port > 0 {
            try await check(hosts: ["127.0.0.1"], port: port, interface: nil)
            return
        }
        #endif
        let network = try await MixerScanNetwork.current()
        try Task.checkCancellation()
        isPartial = network.isPartial
        try await check(hosts: network.hosts, port: 53000, interface: network.interface)
    }

    private func check(hosts: [String], port: UInt16, interface: NWInterface?) async throws {
        try Task.checkCancellation()
        total = hosts.count
        let clientID = PreSonusWire.clientIdentifier
        try await withThrowingTaskGroup(of: DiscoveredMixer?.self) { group in
            var remaining = hosts.makeIterator()
            let identify: @Sendable (String) async throws -> DiscoveredMixer? = { host in
                let name = try await StudioLiveProbe.identify(host: host, port: port,
                                                              interface: interface, clientID: clientID)
                return name.map { DiscoveredMixer(name: $0, host: host, port: port) }
            }
            // Keep the number of active sockets bounded, even on a large venue network.
            for _ in 0..<min(12, hosts.count) {
                if let host = remaining.next() { group.addTask { try await identify(host) } }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                checked += 1
                if let result { mixers.append(result) }
                if let host = remaining.next() { group.addTask { try await identify(host) } }
            }
        }
    }

    deinit { task?.cancel() }
}
