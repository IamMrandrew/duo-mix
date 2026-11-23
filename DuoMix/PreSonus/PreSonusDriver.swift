import Foundation
import Network

/// Direct, bidirectional control over the StudioLive's Ethernet control port.
@MainActor
final class PreSonusDriver: MixerDriver {
    var onEvent: ((MixerEvent) -> Void)?

    private let host: String
    private let port: UInt16
    private let decodeQueue = DispatchQueue(label: "DuoMix.UCNET.decode", qos: .userInitiated)
    private var connection: NWConnection?
    private var meterConnection: NWConnection?
    private var nextMeterDelivery = ContinuousClock.now
    private var latestMeter: [Int: Double]?
    private var meterDeliveryTask: Task<Void, Never>?
    private var writableChannels = Set<Int>()
    private var deadline: Task<Void, Never>?
    private var keepAlive: Task<Void, Never>?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func start() {
        stop()
        guard !host.isEmpty, let endpoint = NWEndpoint.Port(rawValue: port), port != 0 else {
            onEvent?(.failure("Enter the console address and a valid port."))
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionDropTime = 8
        let peer = NWConnection(host: .init(host), port: endpoint, using: NWParameters(tls: nil, tcp: tcp))
        connection = peer
        peer.stateUpdateHandler = { [weak self, weak peer] state in
            Task { @MainActor in
                guard let self, let peer, self.connection === peer else { return }
                switch state {
                case .ready: self.subscribe(to: peer)
                case .failed(let error): self.fail(error.localizedDescription, peer: peer)
                case .waiting(let error):
                    // Network.framework can wait while iOS asks for Local Network
                    // access. The handshake deadline bounds that first attempt.
                    if !self.writableChannels.isEmpty { self.fail(error.localizedDescription, peer: peer) }
                case .cancelled: self.fail("The console connection closed.", peer: peer)
                default: break
                }
            }
        }
        deadline = Task { [weak self, weak peer] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, let peer else { return }
            self.fail("The console did not supply its channel state. Check its address, local network access, and UCNET permissions.", peer: peer)
        }
        peer.start(queue: .main)
    }

    func stop() {
        deadline?.cancel()
        keepAlive?.cancel()
        deadline = nil
        keepAlive = nil
        writableChannels.removeAll()
        stopMetering()
        let old = connection
        connection = nil
        old?.stateUpdateHandler = nil
        old?.cancel()
    }

    func setLevel(_ value: Double, channel: Int) {
        guard let peer = connection, writableChannels.contains(channel), (0...1).contains(value) else { return }
        send(PreSonusWire.parameter("volume", channel: channel, value: Float(value)), to: peer)
    }

    func setMute(_ muted: Bool, channel: Int) {
        guard let peer = connection, writableChannels.contains(channel) else { return }
        send(PreSonusWire.parameter("mute", channel: channel, value: muted ? 1 : 0), to: peer)
    }

    private func subscribe(to peer: NWConnection) {
        // The desk associates its permissions with this installation's identifier.
        let key = "PreSonus.clientIdentifier"
        let id = UserDefaults.standard.string(forKey: key)
            ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        UserDefaults.standard.set(id, forKey: key)
        do {
            send(try PreSonusWire.subscribe(id: id), to: peer)
            receive(from: peer, decoder: PreSonusStream())
            keepAlive = Task { [weak self, weak peer] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, let self, let peer, self.connection === peer else { return }
                    self.send(PreSonusWire.frame("KA"), to: peer)
                    self.startMetering(from: peer)
                }
            }
        } catch {
            fail(error.localizedDescription, peer: peer)
        }
    }

    private func startMetering(from desk: NWConnection) {
        guard !writableChannels.isEmpty, meterConnection == nil,
              let endpoint = desk.currentPath?.remoteEndpoint else { return }
        // A connected UDP socket accepts only datagrams from this console's
        // resolved address and port. The desk learns our local port through TCP.
        let udp = NWConnection(to: endpoint, using: .udp)
        meterConnection = udp
        udp.stateUpdateHandler = { [weak self, weak udp, weak desk] state in
            Task { @MainActor in
                guard let self, let udp, let desk, self.connection === desk, self.meterConnection === udp else { return }
                switch state {
                case .ready:
                    guard case let .hostPort(_, port) = udp.currentPath?.localEndpoint, port != .any else {
                        self.stopMetering()
                        return
                    }
                    self.receiveMeter(from: udp)
                    self.send(PreSonusWire.meterRegistration(port: port.rawValue), to: desk)
                case .failed, .cancelled:
                    self.stopMetering()
                    self.onEvent?(.meters([:]))
                default: break
                }
            }
        }
        udp.start(queue: .main)
    }

    private func receiveMeter(from udp: NWConnection) {
        udp.receiveMessage { [weak self, weak udp] data, _, _, error in
            Task { @MainActor in
                guard let self, let udp, self.meterConnection === udp else { return }
                if let data, let levels = PreSonusMeter.inputLevels(data) {
                    self.deliverMeter(levels.filter { self.writableChannels.contains($0.key) })
                }
                if error != nil {
                    self.stopMetering()
                    self.onEvent?(.meters([:]))
                } else if self.meterConnection === udp {
                    self.receiveMeter(from: udp)
                }
            }
        }
    }

    // Present at most 15 readings per second. A later UDP sample replaces one
    // waiting for the next display update. An idle socket needs no display timer.
    private func deliverMeter(_ levels: [Int: Double]) {
        latestMeter = levels
        guard meterDeliveryTask == nil else { return }
        if ContinuousClock.now >= nextMeterDelivery {
            flushMeter()
        } else {
            let deadline = nextMeterDelivery
            meterDeliveryTask = Task { [weak self] in
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                self?.flushMeter()
            }
        }
    }

    private func flushMeter() {
        guard let levels = latestMeter else { return }
        latestMeter = nil
        meterDeliveryTask = nil
        nextMeterDelivery = .now + .milliseconds(67)
        onEvent?(.meters(levels))
    }

    private func stopMetering() {
        meterDeliveryTask?.cancel()
        meterDeliveryTask = nil
        latestMeter = nil
        nextMeterDelivery = .now
        let udp = meterConnection
        meterConnection = nil
        udp?.stateUpdateHandler = nil
        udp?.cancel()
    }

    private func send(_ data: Data, to peer: NWConnection) {
        peer.send(content: data, completion: .contentProcessed { [weak self, weak peer] error in
            guard let error else { return }
            Task { @MainActor in
                guard let peer else { return }
                self?.fail(error.localizedDescription, peer: peer)
            }
        })
    }

    private func receive(from peer: NWConnection, decoder: PreSonusStream) {
        let queue = decodeQueue
        peer.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak peer] data, _, eof, error in
            queue.async { [weak self, weak peer] in
                let result = Result { try decoder.feed(data ?? Data()) }
                Task { @MainActor [weak self, weak peer] in
                    guard let self, let peer, self.connection === peer else { return }
                    do {
                        for event in try result.get() {
                            guard self.connection === peer else { return }
                            if case .snapshot(let channels) = event {
                                self.writableChannels = Set(channels.map(\.id))
                                self.deadline?.cancel()
                                self.deadline = nil
                                self.startMetering(from: peer)
                            }
                            self.onEvent?(event)
                        }
                        if let error { throw error }
                        guard self.connection === peer else { return }
                        if eof {
                            self.fail("The console closed the connection.", peer: peer)
                        } else {
                            self.receive(from: peer, decoder: decoder)
                        }
                    } catch {
                        self.fail(error.localizedDescription, peer: peer)
                    }
                }
            }
        }
    }

    private func fail(_ message: String, peer: NWConnection) {
        guard connection === peer else { return }
        stop()
        onEvent?(.failure(message))
    }
}
