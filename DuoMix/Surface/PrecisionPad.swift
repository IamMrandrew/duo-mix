import SwiftUI

struct PrecisionPad: View {
    let channel: MixerChannel
    let setLevel: (Double) -> Void

    @GestureState private var contact: CGPoint?
    @State private var dragOrigin: Double?
    @State private var haptics = FaderHaptics(divisions: 100)
    private var touching: Bool { contact != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fine control").font(.headline)
                    Text("\(Desk.number(channel.id)) · \(channel.name)")
                        .font(.subheadline).foregroundStyle(Desk.detail).lineLimit(1)
                }
                Spacer(minLength: 0)
                nudge("minus", label: "Lower fader one percent", amount: -0.01)
                nudge("plus", label: "Raise fader one percent", amount: 0.01)
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Desk.background, Desk.panel],
                                             startPoint: .top, endPoint: .bottomTrailing))
                    Canvas { context, size in
                        var dots = Path()
                        for y in stride(from: CGFloat(9), to: size.height - 3, by: 14) {
                            for x in stride(from: CGFloat(9), to: size.width - 3, by: 14) {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                            }
                        }
                        context.fill(dots, with: .color(Desk.detail.opacity(0.22)))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    if let contact {
                        Circle().strokeBorder(Desk.accent.opacity(0.85), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                            .position(contact)
                    } else {
                        Label("Drag up or down", systemImage: "arrow.up.and.down")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Desk.detail)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(LinearGradient(colors: [.black.opacity(0.85), Desk.line],
                                                 startPoint: .top, endPoint: .bottom)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .updating($contact) { drag, state, _ in state = drag.location }
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
            .accessibilityLabel("Fine fader position for \(channel.name)")
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
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 7).fill(Desk.raised))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Desk.line))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(amount > 0 ? "fine-up" : "fine-down")
    }
}
