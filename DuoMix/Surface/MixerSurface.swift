import SwiftUI

enum Desk {
    static let background = Color(red: 0.065, green: 0.074, blue: 0.078)
    static let panel = Color(red: 0.102, green: 0.116, blue: 0.122)
    static let raised = Color(red: 0.143, green: 0.160, blue: 0.168)
    static let line = Color.white.opacity(0.13)
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.93)
    static let detail = Color(red: 0.68, green: 0.72, blue: 0.71)
    static let mint = Color(red: 0.59, green: 0.92, blue: 0.75)
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.43)
    static let muted = Color(red: 1.0, green: 0.53, blue: 0.44)

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
        case .demo: Desk.amber
        case .connecting: Desk.amber
        case .live: Desk.mint
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
    private var isDemo: Bool { store.status == .demo }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let division = activeDivision(proxy)
            if let division, division.width > division.height {
                VStack(spacing: 0) {
                    bankDeck(width: size.width, height: division.minY)
                        .frame(height: division.minY)
                    Spacer().frame(height: division.height)
                    precisionDeck
                }
            } else if let division {
                HStack(spacing: 0) {
                    bankDeck(width: division.minX, height: size.height)
                        .frame(width: division.minX)
                    Spacer().frame(width: division.width)
                    precisionDeck
                }
            } else if size.width >= 900 || (size.width >= 640 && size.height < 470) {
                let padWidth = min(320, max(215, size.width * 0.31))
                HStack(spacing: 0) {
                    bankDeck(width: size.width - padWidth - 1, height: size.height)
                    Rectangle().fill(Desk.line).frame(width: 1)
                    precisionDeck.frame(width: padWidth)
                }
            } else {
                let height = min(245, max(146, size.height * 0.30))
                VStack(spacing: 0) {
                    bankDeck(width: size.width, height: size.height - height - 1)
                    Rectangle().fill(Desk.line).frame(height: 1)
                    precisionDeck.frame(height: height)
                }
            }
        }
        .background(Desk.background.ignoresSafeArea())
        .foregroundStyle(Desk.ink)
        .tint(Desk.mint)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(store: store)
        }
    }

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
    private func bankDeck(width: CGFloat, height: CGFloat) -> some View {
        let margin: CGFloat = width < 455 ? 12 : 18
        let compact = height < 370
        let preferredStripWidth: CGFloat = typeSize.isAccessibilitySize ? 110 : 65
        let count = max(1, min(8, Int((width - 2 * margin) / (preferredStripWidth + 6))))
        let selectedIndex = store.channels.firstIndex { $0.id == store.selectedID } ?? 0
        let start = (selectedIndex / count) * count
        let bank = Array(store.channels.dropFirst(start).prefix(count))
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.vertical.3").foregroundStyle(Desk.mint).accessibilityHidden(true)
                    Text("Duo Mix").font(.headline.weight(.semibold))
                }
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button { showConnection = true } label: {
                    HStack(spacing: 7) {
                        if isDemo {
                            Label("Connect", systemImage: "cable.connector")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Desk.mint)
                        } else {
                            Circle().fill(awaitingDesk ? Desk.amber : store.status.indicator).frame(width: 7, height: 7)
                            Text(connectionName).font(Desk.label())
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(Desk.raised))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDemo ? "Connect to a mixer" : "Mixer connection, \(connectionName)")
                .accessibilityIdentifier("connections")
            }
            .padding(.horizontal, 2)
            Rectangle().fill(Desk.line).frame(height: 1)
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDemo ? "Demo desk" : "Main mix")
                        .font(.system(size: compact ? 21 : 27, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(isDemo ? "demo-desk-title" : "main-mix-title")
                    if isDemo && height >= 300 && width >= 310 {
                        Text("Offline practice · \(store.channels.count) inputs")
                            .font(.caption).foregroundStyle(Desk.detail)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                if let first = bank.first, let last = bank.last {
                    Text("\(Desk.number(first.id))–\(Desk.number(last.id))")
                        .font(Desk.label()).foregroundStyle(Desk.detail)
                        .accessibilityLabel("Inputs \(first.id) through \(last.id)")
                }
                bankButton("Previous inputs", icon: "chevron.left", identifier: "previous-bank",
                           enabled: start > 0) {
                    store.select(store.channels[max(0, start - count)].id)
                }
                bankButton("Next inputs", icon: "chevron.right", identifier: "next-bank",
                           enabled: start + count < store.channels.count) {
                    store.select(store.channels[start + count].id)
                }
            }
            if bank.isEmpty || !store.canMix {
                disconnectedBank
            } else {
                HStack(spacing: 5) {
                    ForEach(bank, id: \.id) { channel in
                        ChannelStrip(channel: channel, selected: channel.id == store.selectedID,
                                     compact: compact, select: { store.select(channel.id) },
                                     setLevel: { store.setLevel($0, channel: channel.id) },
                                     toggleMute: { store.setMute(!channel.isMuted, channel: channel.id) })
                        .frame(maxWidth: .infinity)
                    }
                    if bank.count < count {
                        ForEach(bank.count..<count, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .id(store.status.displayName)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, compact ? 0 : 4)
        .padding(.bottom, compact ? 5 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var disconnectedBank: some View {
        VStack(spacing: 9) {
            if case .connecting = store.status {
                ProgressView().tint(Desk.mint)
                Text("Waiting for mixer state").font(.headline)
            } else {
                Image(systemName: "cable.connector").font(.title2).foregroundStyle(Desk.detail)
                Text("Mixer offline").font(.headline)
                HStack(spacing: 16) {
                    Button("Connect") { showConnection = true }
                    Button("Open demo desk") { store.useDemo() }
                        .accessibilityIdentifier("offline-open-demo")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Desk.mint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Desk.panel))
    }

    private func bankButton(_ label: String, icon: String, identifier: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .frame(width: 29, height: 27)
                .background(RoundedRectangle(cornerRadius: 6).fill(Desk.raised))
                .frame(width: 44, height: 44)
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
