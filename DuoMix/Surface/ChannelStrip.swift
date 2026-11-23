import SwiftUI

struct ChannelStrip: View {
    let channel: MixerChannel
    let selected: Bool
    let compact: Bool
    let select: () -> Void
    let setLevel: (Double) -> Void
    let toggleMute: () -> Void

    @State private var dragOrigin: Double?
    @GestureState private var isDragging = false
    @State private var haptics = FaderHaptics(divisions: 10)

    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                VStack(spacing: 3) {
                    Text(Desk.number(channel.id)).font(Desk.label(10))
                        .foregroundStyle(selected ? Desk.mint : Desk.detail)
                    Text(channel.name).font(.caption.weight(.semibold))
                        .lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select input \(channel.id), \(channel.name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("channel-\(channel.id)")
            Divider().overlay(Desk.line).padding(.horizontal, 5)
            GeometryReader { geometry in
                let inset: CGFloat = compact ? 6 : 10
                let travel = max(1, geometry.size.height - 2 * inset)
                faderLane(inset: inset)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .updating($isDragging) { _, active, _ in active = true }
                    .onChanged { drag in
                        if dragOrigin == nil {
                            dragOrigin = channel.level
                            haptics.begin(at: channel.level, time: drag.time)
                            select()
                        }
                        if let dragOrigin {
                            let level = min(1, max(0, dragOrigin - drag.translation.height / travel))
                            haptics.move(to: level, time: drag.time)
                            setLevel(level)
                        }
                    }
                    .onEnded { _ in dragOrigin = nil })
                .onChange(of: isDragging) { _, active in
                    if !active { dragOrigin = nil }
                }
                .onTapGesture(perform: select)
            }
            .padding(.vertical, compact ? 2 : 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(channel.name) fader")
            .accessibilityValue(Desk.position(channel.level))
            .accessibilityAdjustableAction { direction in
                select()
                switch direction {
                case .increment: setLevel(min(1, channel.level + 0.01))
                case .decrement: setLevel(max(0, channel.level - 0.01))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("fader-\(channel.id)")
            Text(Desk.position(channel.level)).font(Desk.label(compact ? 11 : 13))
                .foregroundStyle(selected ? Desk.mint : Desk.ink)
                .accessibilityHidden(true)
            Button {
                select()
                toggleMute()
            } label: {
                Text(channel.isMuted ? "MUTED" : "MUTE")
                    .font(Desk.label(10)).tracking(0.5)
                    .foregroundStyle(channel.isMuted ? Desk.background : Desk.detail)
                    .frame(maxWidth: .infinity).frame(height: 27)
                    .background(RoundedRectangle(cornerRadius: 5).fill(channel.isMuted ? Desk.muted : Desk.raised))
                    .padding(.horizontal, 5)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mute \(channel.name)")
            .accessibilityValue(channel.isMuted ? "On" : "Off")
            .accessibilityIdentifier("mute-\(channel.id)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Desk.raised : Desk.panel))
        .overlay(alignment: .top) {
            Capsule().fill(selected ? Desk.mint : Desk.line)
                .frame(width: 22, height: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Desk.mint.opacity(0.65) : Desk.line))
        .sensoryFeedback(trigger: haptics.pulse) { _, pulse in pulse.kind.feedback }
    }

    private func faderLane(inset: CGFloat) -> some View {
        Canvas { context, size in
            let travel = max(1, size.height - 2 * inset)
            let width = min(40, size.width * 0.46)
            let lane = CGRect(x: (size.width - width) / 2, y: inset,
                              width: width, height: travel)
            let outline = Path(roundedRect: lane, cornerRadius: 6)
            let markerY = lane.maxY - travel * CGFloat(channel.level)
            let fill = selected ? Desk.mint : Color(red: 0.53, green: 0.65, blue: 0.62)

            context.fill(outline, with: .color(Desk.background))
            context.drawLayer { layer in
                layer.clip(to: outline)
                let filled = CGRect(x: lane.minX, y: markerY, width: width,
                                    height: max(0, lane.maxY - markerY))
                layer.fill(Path(filled), with: .color(fill.opacity(channel.isMuted ? 0.22 : 0.53)))
            }
            context.stroke(outline, with: .color(Desk.line), lineWidth: 1)

            // Quarter marks stay outside the fill so the position reads clearly at a glance.
            var ticks = Path()
            for quarter in 1...3 {
                let y = lane.minY + travel * CGFloat(quarter) / 4
                ticks.move(to: CGPoint(x: lane.maxX + 3, y: y))
                ticks.addLine(to: CGPoint(x: lane.maxX + (quarter == 2 ? 8 : 6), y: y))
            }
            context.stroke(ticks, with: .color(Desk.detail.opacity(0.55)), lineWidth: 1)
            let markerHeight: CGFloat = isDragging ? 7 : 5
            let marker = CGRect(x: lane.minX - 3, y: markerY - markerHeight / 2,
                                width: width + 6, height: markerHeight)
            context.fill(Path(roundedRect: marker, cornerRadius: markerHeight / 2),
                         with: .color(selected ? Desk.mint : Desk.ink))
        }
    }
}
