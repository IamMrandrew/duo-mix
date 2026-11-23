import Foundation
import Network

enum StudioLiveProbe {
    /// Identify one candidate from its UCNET subscription reply and synchronized input state.
    static func identify(host: String, port: UInt16, interface: NWInterface?, clientID: String) async throws -> String? {
        try Task.checkCancellation()
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredInterface = interface
        let peer = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        let attempt = Handshake(peer: peer, request: try PreSonusWire.subscribe(id: clientID))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { attempt.start($0) }
        } onCancel: {
            attempt.cancel()
        }
    }
}

/// All mutable state and socket callbacks are serialized on this connection's queue.
private final class Handshake: @unchecked Sendable {
    private let peer: NWConnection
    private let request: Data
    private let queue = DispatchQueue(label: "DuoMix.UCNET.identify")
    private let decoder = PreSonusStream()
    private var byteCount = 0
    private var cancelled = false
    private var continuation: CheckedContinuation<String?, Error>?
    private var timeout: DispatchWorkItem?

    init(peer: NWConnection, request: Data) {
        self.peer = peer
        self.request = request
    }

    func start(_ continuation: CheckedContinuation<String?, Error>) {
        queue.async {
            guard !self.cancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            self.peer.stateUpdateHandler = { state in
                guard self.continuation != nil else { return }
                switch state {
                case .ready:
                    self.armTimeout(seconds: 3)
                    self.peer.send(content: self.request, completion: .contentProcessed { error in
                        if error != nil { self.finish(.success(nil)) }
                    })
                    self.receive()
                case .waiting, .failed:
                    self.finishUnreachable()
                case .cancelled:
                    self.finish(.success(nil))
                default: break
                }
            }
            self.armTimeout(seconds: 1)
            self.peer.start(queue: self.queue)
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            self.finish(.failure(CancellationError()))
        }
    }

    private func armTimeout(seconds: Int) {
        timeout?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.finishUnreachable() }
        timeout = item
        queue.asyncAfter(deadline: .now() + .seconds(seconds), execute: item)
    }

    private func receive() {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, eof, error in
            guard self.continuation != nil else { return }
            if let data {
                self.byteCount += data.count
                guard self.byteCount <= PreSonusSnapshot.maximumSize,
                      let events = try? self.decoder.feed(data) else {
                    self.finish(.success(nil))
                    return
                }
                for event in events {
                    if case .snapshot = event {
                        self.finish(.success(self.decoder.mixerName ?? "StudioLive"))
                        return
                    }
                }
            }
            if eof || error != nil { self.finishUnreachable() }
            else { self.receive() }
        }
    }

    private func finishUnreachable() {
        if peer.currentPath?.unsatisfiedReason == .localNetworkDenied {
            finish(.failure(StudioLiveScanError.localNetworkDenied))
        } else {
            finish(.success(nil))
        }
    }

    private func finish(_ result: Result<String?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        peer.stateUpdateHandler = nil
        peer.cancel()
        continuation.resume(with: result)
    }
}
