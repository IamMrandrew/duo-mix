import SwiftUI

struct ChannelStrip: View {
    let channel: MixerChannel
    let selected: Bool
    let compact: Bool
    let meters: MixerMeters
    let select: () -> Void
    let setLevel: (Double) -> Void
    let toggleMute: () -> Void

    @State private var dragOrigin: Double?
    @GestureState private var isDragging = false
    @State private var haptics = FaderHaptics(divisions: 10)
    @ScaledMetric(relativeTo: .subheadline) private var headerHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                VStack(spacing: 2) {
                    Text(Desk.number(channel.id)).font(Desk.label(12))
                        .foregroundStyle(selected ? Desk.accent : Desk.detail)
                    Text(channel.name).font(.subheadline.weight(.semibold))
                        .lineLimit(channel.name.contains(where: \.isWhitespace) ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select input \(channel.id), \(channel.name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("channel-\(channel.id)")
            Rectangle().fill(Desk.line).frame(height: 1).padding(.horizontal, 7)
            ZStack {
                GeometryReader { geometry in
                    let available = max(0, geometry.size.height - ChannelSignalMeter.readingHeight)
                    let inset = FaderChisel.travelInset(forHeight: available)
                    let travel = max(1, available - 2 * inset)
                    FaderChisel(level: channel.level, selected: selected, isDragging: isDragging, inset: inset)
                        .padding(.top, ChannelSignalMeter.readingHeight)
                        .padding(.trailing, 7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(channel.name) fader position")
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

                ChannelSignalMeter(meters: meters, channelID: channel.id, channelName: channel.name)
                    .allowsHitTesting(false)
            }
            .padding(.vertical, compact ? 1 : 4)
            Button {
                select()
                toggleMute()
            } label: {
                Text(channel.isMuted ? "Muted" : "Mute")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(channel.isMuted ? Desk.background : Desk.ink)
                    .frame(maxWidth: .infinity).frame(minHeight: compact ? 40 : 44)
                    .background(RoundedRectangle(cornerRadius: 6).fill(channel.isMuted ? Desk.muted : Desk.raised))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Desk.line))
                    .padding(.horizontal, 3)
                    .padding(.vertical, compact ? 3 : 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mute \(channel.name)")
            .accessibilityValue(channel.isMuted ? "On" : "Off")
            .accessibilityIdentifier("mute-\(channel.id)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? Desk.raised : Desk.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(selected ? Desk.accent : Desk.line).frame(height: selected ? 2 : 1)
        }
        .sensoryFeedback(trigger: haptics.pulse) { _, pulse in pulse.kind.feedback }
    }
}
