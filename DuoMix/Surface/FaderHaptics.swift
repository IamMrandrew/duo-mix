import SwiftUI

/// Feedback follows the operator's finger. Network updates never enter this path.
struct FaderHaptics {
    enum Kind {
        case pickup, tick, endStop

        var feedback: SensoryFeedback {
            switch self {
            case .pickup: .impact(weight: .light, intensity: 0.45)
            case .tick: .selection
            case .endStop: .impact(weight: .medium, intensity: 0.75)
            }
        }
    }

    struct Pulse: Equatable {
        var sequence = 0
        var kind = Kind.pickup
    }

    let divisions: Int
    private(set) var pulse = Pulse()
    private var lastBand = 0
    private var lastPosition = 0.0
    private var lastTick = Date.distantPast

    init(divisions: Int) { self.divisions = divisions }

    mutating func begin(at position: Double, time: Date) {
        lastPosition = position
        lastBand = band(at: position)
        lastTick = time
        emit(.pickup)
    }

    mutating func move(to position: Double, time: Date) {
        guard position != lastPosition else { return }
        lastPosition = position
        let newBand = band(at: position)
        if position == 0 || position == 1 {
            emit(.endStop)
        } else if newBand != lastBand && time.timeIntervalSince(lastTick) >= 0.075 {
            emit(.tick)
        } else {
            return
        }
        lastBand = newBand
        lastTick = time
    }

    mutating func nudge(to position: Double) {
        emit((position == 0 || position == 1) ? .endStop : .tick)
    }

    private func band(at position: Double) -> Int { Int(position * Double(divisions)) }

    private mutating func emit(_ kind: Kind) {
        pulse.kind = kind
        pulse.sequence &+= 1
    }
}
