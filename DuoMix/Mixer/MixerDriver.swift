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

    func start() {
        let names = ["Kick", "Snare", "Hi-Hat", "Rack Tom", "Floor Tom", "Overheads",
                     "Bass DI", "Guitar", "Keys L", "Keys R", "Lead Vox", "Backing Vox"]
        let levels = [0.72, 0.63, 0.46, 0.54, 0.48, 0.61, 0.69, 0.58, 0.62, 0.62, 0.76, 0.59]
        onEvent?(.snapshot((1...32).map { id in
            let named = id <= names.count
            return MixerChannel(id: id, name: named ? names[id - 1] : "Input \(id)",
                                level: named ? levels[id - 1] : 0, isMuted: !named)
        }))
    }

    func stop() {}
    func setLevel(_ value: Double, channel: Int) { onEvent?(.level(channel: channel, value: value)) }
    func setMute(_ muted: Bool, channel: Int) { onEvent?(.mute(channel: channel, muted: muted)) }
}
