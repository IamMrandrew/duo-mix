import SwiftUI

struct PrecisionPad: View {
    let channel: MixerChannel
    let setLevel: (Double) -> Void

    @GestureState private var touching = false
    @State private var dragOrigin: Double?
    @State private var haptics = FaderHaptics(divisions: 100)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "dial.low").foregroundStyle(Desk.mint)
                Text("Fine control").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(Desk.position(channel.level))
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Desk.mint)
                    .accessibilityLabel("Fader position \(Desk.position(channel.level))")
            }
            HStack(spacing: 6) {
                Text("IN \(Desk.number(channel.id))").font(Desk.label(11))
                    .foregroundStyle(Desk.mint)
                Text(channel.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                nudge("minus", label: "Lower fader one percent", amount: -0.01)
                nudge("plus", label: "Raise fader one percent", amount: 0.01)
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Desk.background)
                    Canvas { context, size in
                        var dots = Path()
                        for y in stride(from: CGFloat(9), to: size.height - 3, by: 14) {
                            for x in stride(from: CGFloat(9), to: size.width - 3, by: 14) {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                            }
                        }
                        context.fill(dots, with: .color(Desk.detail.opacity(0.39)))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Label("Drag up or down", systemImage: "arrow.up.and.down")
                        .font(Desk.label()).foregroundStyle(touching ? Desk.mint : Desk.detail)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Desk.background, in: Capsule())
                }
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(touching ? Desk.mint : Desk.line, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { drag in
                        if dragOrigin == nil {
                            dragOrigin = channel.level
                            haptics.begin(at: channel.level, time: drag.time)
                        }
                        if let dragOrigin {
                            // A full-height stroke changes twenty percent of the fader travel.
                            let delta = -drag.translation.height / max(geometry.size.height, 1) * 0.2
                            let level = min(1, max(0, dragOrigin + delta))
                            haptics.move(to: level, time: drag.time)
                            setLevel(level)
                        }
                    }
                    .onEnded { _ in dragOrigin = nil })
                .onChange(of: touching) { _, active in
                    if !active { dragOrigin = nil }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fine level for \(channel.name)")
            .accessibilityValue(Desk.position(channel.level))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setLevel(min(1, channel.level + 0.01))
                case .decrement: setLevel(max(0, channel.level - 0.01))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("fine-pad")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Desk.panel)
        .sensoryFeedback(trigger: haptics.pulse) { _, pulse in pulse.kind.feedback }
    }

    private func nudge(_ icon: String, label: String, amount: Double) -> some View {
        Button {
            let level = min(1, max(0, channel.level + amount))
            if level != channel.level {
                haptics.nudge(to: level)
                setLevel(level)
            }
        } label: {
            Image(systemName: icon).font(.caption.weight(.bold))
                .frame(width: 30, height: 27)
                .background(RoundedRectangle(cornerRadius: 6).fill(Desk.raised))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(amount > 0 ? "fine-up" : "fine-down")
    }
}
