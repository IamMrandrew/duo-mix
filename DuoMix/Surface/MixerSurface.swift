import SwiftUI

enum Desk {
    static let background = Color(red: 0.082, green: 0.079, blue: 0.075)
    static let panel = Color(red: 0.136, green: 0.131, blue: 0.123)
    static let raised = Color(red: 0.203, green: 0.196, blue: 0.184)
    static let line = Color.white.opacity(0.13)
    static let ink = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let detail = Color(red: 0.72, green: 0.70, blue: 0.67)
    static let accent = Color(.sRGB, red: 1, green: 196 / 255, blue: 0)
    static let live = Color(red: 0.65, green: 0.79, blue: 0.55)
    static let muted = Color(red: 0.96, green: 0.59, blue: 0.51)

    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static func number(_ id: Int) -> String { String(format: "%02d", id) }
    static func position(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

extension MixerStatus {
    var displayName: String {
        switch self {
        case .demo: "Demo"
        case .connecting: "Connecting"
        case .live: "Live"
        case .offline: "Offline"
        }
    }

    var indicator: Color {
        switch self {
        case .demo: Desk.detail
        case .connecting: Desk.accent
        case .live: Desk.live
        case .offline: Desk.muted
        }
    }
}

struct MixerSurface: View {
    @ObservedObject var store: MixerStore
    @State private var showConnection = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var awaitingDesk: Bool { store.status == .live && store.hasPendingWrites }
    private var connectionName: String { awaitingDesk ? "Awaiting desk" : store.status.displayName }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let division = activeDivision(proxy)
            if #available(iOS 27.1, *), let division, division.width > division.height {
                tabletop(outer: proxy, division: division)
            } else {
                bankDeck(width: size.width, height: size.height, verticalHinge: division)
            }
        }
        .background(Desk.background.ignoresSafeArea())
        .foregroundStyle(Desk.ink)
        .tint(Desk.ink)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(store: store)
        }
    }

    @available(iOS 27.1, *)
    private func tabletop(outer: GeometryProxy, division: CGRect) -> some View {
        GeometryReader { full in
            // The outer reader starts inside the safe area. Translate the measured
            // fold into this edge-to-edge reader without shifting the lower pad.
            let safeTop = max(0, outer.frame(in: .global).minY - full.frame(in: .global).minY)
            let foldTop = division.minY + safeTop
            let header = TabletopToolbarLayout(width: full.size.width, margin: bankMargin(full.size.width),
                                               safeTop: safeTop, occlusions: full.reservedRegions(kind: .occlusion).map(\.frame),
                                               accessible: typeSize.isAccessibilitySize)
            VStack(spacing: 0) {
                bankDeck(width: full.size.width, height: foldTop, tabletopHeader: header)
                    .frame(height: foldTop)
                Color.clear.frame(height: division.height)
                precisionDeck
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func bankMargin(_ width: CGFloat) -> CGFloat { width < 455 ? 8 : 12 }

    private func activeDivision(_ proxy: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            let bounds = CGRect(origin: .zero, size: proxy.size)
            for region in proxy.reservedRegions(kind: .division) {
                let frame = region.frame.intersection(bounds)
                guard !frame.isNull else { continue }
                if frame.width > frame.height && frame.minY > 0 && frame.maxY < bounds.height {
                    return frame
                }
                if frame.height > frame.width && frame.minX > 0 && frame.maxX < bounds.width {
                    return frame
                }
            }
        }
        return nil
    }

    @ViewBuilder
    private func bankDeck(width: CGFloat, height: CGFloat, verticalHinge: CGRect? = nil,
                          tabletopHeader: TabletopToolbarLayout? = nil) -> some View {
        let margin = bankMargin(width)
        let compact = height < 370
        let layout = FaderBankLayout(width: width, margin: margin, hinge: verticalHinge,
                                     accessible: typeSize.isAccessibilitySize)
        let count = layout.count
        let selectedIndex = store.channels.firstIndex { $0.id == store.selectedID } ?? 0
        let start = (selectedIndex / count) * count
        let bank = Array(store.channels.dropFirst(start).prefix(count))
        VStack(alignment: .leading, spacing: tabletopHeader != nil || compact ? 4 : 8) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    connectionButton
                    Spacer(minLength: 0)
                }
                .frame(width: layout.firstWidth)
                if let gap = layout.gap { Color.clear.frame(width: gap, height: 1) }
                HStack(spacing: 0) {
                    if layout.gap != nil { Spacer(minLength: 0) }
                    bankButton("Previous inputs", icon: "chevron.left", identifier: "previous-bank",
                               enabled: start > 0) { store.select(store.channels[max(0, start - count)].id) }
                    if let first = bank.first, let last = bank.last {
                        Text("\(Desk.number(first.id))–\(Desk.number(last.id))")
                            .font(Desk.label(13)).foregroundStyle(Desk.ink)
                            .lineLimit(1).fixedSize()
                            .accessibilityLabel("Inputs \(first.id) through \(last.id)")
                            .accessibilityIdentifier("visible-inputs")
                    }
                    bankButton("Next inputs", icon: "chevron.right", identifier: "next-bank",
                               enabled: start + count < store.channels.count) { store.select(store.channels[start + count].id) }
                }
            }
            .padding(.leading, tabletopHeader?.leadingInset ?? 0)
            .padding(.trailing, tabletopHeader?.trailingInset ?? 0)
            .padding(.top, tabletopHeader?.rowTop ?? 0)
            .frame(minHeight: tabletopHeader?.height, alignment: .top)
            if bank.isEmpty || !store.canMix {
                disconnectedBank
            } else {
                HStack(spacing: 0) {
                    strips(bank.prefix(layout.firstCount), slots: layout.firstCount, compact: compact)
                        .frame(width: layout.firstWidth)
                    if let gap = layout.gap {
                        Color.clear.frame(width: gap)
                        strips(bank.dropFirst(layout.firstCount), slots: layout.secondCount, compact: compact)
                    }
                }
                .id(store.status.displayName)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, tabletopHeader != nil || compact ? 0 : 4)
        .padding(.bottom, tabletopHeader != nil ? 2 : compact ? 5 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var connectionButton: some View {
        Button { showConnection = true } label: {
            HStack(spacing: 5) {
                Circle().fill(awaitingDesk ? Desk.accent : store.status.indicator).frame(width: 7, height: 7)
                ViewThatFits(in: .horizontal) {
                    Text(connectionName).fixedSize()
                    Text(store.status.displayName).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10).frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 7).fill(Desk.raised))
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mixer connection, \(connectionName)")
        .accessibilityIdentifier("connections")
    }

    private func strips(_ bank: ArraySlice<MixerChannel>, slots: Int, compact: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(bank) { channel in
                ChannelStrip(channel: channel, selected: channel.id == store.selectedID,
                             compact: compact, meters: store.meters, select: { store.select(channel.id) },
                             setLevel: { store.setLevel($0, channel: channel.id) },
                             toggleMute: { store.setMute(!channel.isMuted, channel: channel.id) })
                    .frame(maxWidth: .infinity)
            }
            ForEach(bank.count..<slots, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
        }
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Desk.line))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disconnectedBank: some View {
        VStack(spacing: 9) {
            if case .connecting = store.status {
                ProgressView().tint(Desk.ink)
                Text("Waiting for mixer state").font(.headline)
            } else {
                Image(systemName: "cable.connector").font(.title2).foregroundStyle(Desk.detail)
                Text("Mixer offline").font(.headline)
                HStack(spacing: 16) {
                    Button("Connect") { showConnection = true }
                    Button("Use demo") { store.useDemo() }
                        .accessibilityIdentifier("offline-open-demo")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Desk.ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Desk.panel))
    }

    private func bankButton(_ label: String, icon: String, identifier: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 41, height: 40)
                .background(RoundedRectangle(cornerRadius: 7).fill(Desk.raised))
                .frame(width: 46, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var precisionDeck: some View {
        if let channel = store.selected, store.canMix {
            PrecisionPad(channel: channel, setLevel: { store.setLevel($0, channel: channel.id) })
                .id("\(store.status.displayName)-\(channel.id)")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "hand.draw")
                Text("Fine control").font(.subheadline)
            }
            .foregroundStyle(Desk.detail)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Desk.panel)
        }
    }
}
