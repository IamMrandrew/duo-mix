import SwiftUI

/// Only this part of the strip observes the input meter stream.
struct ChannelSignalMeter: View {
    @ObservedObject var meters: MixerMeters
    let channelID: Int
    let channelName: String
    static let readingHeight: CGFloat = 24

    var body: some View {
        let db = meters.levels[channelID]
        let display = reading(db)
        VStack(spacing: 0) {
            Text("\(display) dB")
                .font(Desk.label(13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(db.map { $0 >= -1 && $0.isFinite } == true ? Desk.muted : Desk.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Self.readingHeight)
            Canvas { context, size in
                let inset = FaderChisel.travelInset(forHeight: size.height)
                let rail = CGRect(x: max(0, size.width - 7), y: inset, width: 3.5,
                                  height: max(0, size.height - 2 * inset))
                context.fill(Path(rail), with: .color(.black.opacity(0.45)))
                guard let db, db.isFinite else { return }
                // Sixty decibels of display range. Only the drawing clips at the floor.
                let fraction = min(1, max(0, (db + 60) / 60))
                let height = rail.height * fraction
                let bar = CGRect(x: rail.minX, y: rail.maxY - height, width: rail.width, height: height)
                let color = db >= -1 ? Desk.muted : db >= -6 ? Desk.accent : Desk.detail
                context.fill(Path(bar), with: .color(color))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(channelName) input meter")
        .accessibilityValue(accessibleReading(db))
        .accessibilityIdentifier("meter-\(channelID)")
    }

    private func reading(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == -.infinity { return "−∞" }
        guard value.isFinite else { return "—" }
        let rounded = value.rounded()
        if rounded == 0 { return "0" }
        return String(format: "%.0f", rounded).replacingOccurrences(of: "-", with: "−")
    }

    private func accessibleReading(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        if value == -.infinity { return "Silence" }
        guard value.isFinite else { return "Unavailable" }
        return "Approximately \(reading(value)) decibels full scale"
    }
}
