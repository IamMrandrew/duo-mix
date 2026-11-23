import Foundation

struct MixerChannel: Identifiable, Equatable {
    let id: Int
    var name: String
    /// Normalized fader travel. Each driver handles its own console's wire units.
    var level: Double
    var isMuted: Bool
}

enum MixerEvent {
    case snapshot([MixerChannel])
    case level(channel: Int, value: Double)
    case mute(channel: Int, muted: Bool)
    case name(channel: Int, name: String)
    /// One input-meter frame in dB. A silent input reads -infinity.
    /// A missing channel has no reading in this frame.
    case meters([Int: Double])
    case failure(String)
}

@MainActor
protocol MixerDriver: AnyObject {
    var onEvent: ((MixerEvent) -> Void)? { get set }
    func start()
    func stop()
    func setLevel(_ value: Double, channel: Int)
    func setMute(_ muted: Bool, channel: Int)
}

enum MixerStatus: Equatable {
    case demo, connecting, live
    case offline(String)
}

@MainActor
final class DemoDriver: MixerDriver {
    var onEvent: ((MixerEvent) -> Void)?
    private var channels: [MixerChannel]
    private var meterTask: Task<Void, Never>?

    init() {
        let names = ["Kick", "Snare", "Hi-Hat", "Rack Tom", "Floor Tom", "Overheads",
                     "Bass DI", "Guitar", "Keys L", "Keys R", "Lead Vox", "Backing Vox"]
        let levels = [0.72, 0.63, 0.46, 0.54, 0.48, 0.61, 0.69, 0.58, 0.62, 0.62, 0.76, 0.59]
        channels = (1...32).map { id in
            let named = id <= names.count
            return MixerChannel(id: id, name: named ? names[id - 1] : "Input \(id)",
                                level: named ? levels[id - 1] : 0, isMuted: !named)
        }
    }

    func start() {
        stop()
        onEvent?(.snapshot(channels))
        meterTask = Task { [weak self] in
            var time = 0.0
            while !Task.isCancelled {
                guard self != nil else { return }
                var levels = [Int: Double]()
                for id in 1...12 {
                    let phase = time * (3.5 + Double(id % 5) * 0.31) + Double(id)
                    let pulse = pow(max(0, cos(phase)), 3)
                    levels[id] = -32 + 25 * pulse + 3 * sin(phase * 0.61)
                }
                for id in 13...32 { levels[id] = -.infinity }
                self?.onEvent?(.meters(levels))
                time += 0.1
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    func stop() {
        meterTask?.cancel()
        meterTask = nil
    }

    deinit { meterTask?.cancel() }

    func setLevel(_ value: Double, channel: Int) {
        guard let index = channels.firstIndex(where: { $0.id == channel }) else { return }
        channels[index].level = value
        onEvent?(.level(channel: channel, value: value))
    }

    func setMute(_ muted: Bool, channel: Int) {
        guard let index = channels.firstIndex(where: { $0.id == channel }) else { return }
        channels[index].isMuted = muted
        onEvent?(.mute(channel: channel, muted: muted))
    }
}
