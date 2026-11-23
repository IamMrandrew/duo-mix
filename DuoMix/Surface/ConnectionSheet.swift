import SwiftUI

struct ConnectionSheet: View {
    @ObservedObject var store: MixerStore
    @StateObject private var discovery = MixerDiscovery()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var field: Field?

    private enum Field { case host, port }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(store.status.displayName, systemImage: "circle.fill")
                            .font(.headline)
                            .foregroundStyle(store.status.indicator)
                        Spacer()
                        if case .connecting = store.status { ProgressView() }
                    }
                    switch store.status {
                    case .demo:
                        Text("Demo uses simulated input signals.").foregroundStyle(.secondary)
                    case .connecting:
                        Text("Waiting for the console to send its channel state.").foregroundStyle(.secondary)
                    case .live:
                        Text(store.hasPendingWrites
                             ? "Faders show your requested settings while the desk confirms them."
                             : "Input meters show estimated dBFS from the console.")
                            .foregroundStyle(.secondary)
                    case .offline(let message):
                        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button(demoActionTitle) {
                        field = nil
                        if store.status != .demo { store.useDemo() }
                        dismiss()
                    }
                    .accessibilityIdentifier("use-demo")
                }
                if !sessionActive { discoverySection }
                Section {
                    LabeledContent("Mixer") {
                        Text("StudioLive 32SX").foregroundStyle(.secondary)
                    }
                    LabeledContent("Address") {
                        TextField("Mixer IP or hostname", text: $store.host)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().focused($field, equals: .host)
                            .submitLabel(.next).onSubmit { field = .port }
                            .accessibilityLabel("Mixer address").accessibilityIdentifier("mixer-host")
                    }
                    LabeledContent("TCP port") {
                        TextField("53000", text: $store.port)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad).focused($field, equals: .port)
                            .accessibilityLabel("TCP port").accessibilityIdentifier("mixer-port")
                    }
                } header: {
                    Text("Manual connection")
                } footer: {
                    Text("Use the address shown on the console’s UCNET screen.")
                }
                .disabled(sessionActive)
                Section {
                    switch store.status {
                    case .connecting:
                        Button("Cancel connection") { field = nil; store.disconnect() }
                    case .live:
                        Button("Disconnect") { store.disconnect() }
                    case .demo, .offline:
                        Button("Connect to mixer") { connect() }
                            .disabled(!validEndpoint)
                            .accessibilityIdentifier("connect-mixer")
                    }
                }
            }
            .navigationTitle("Mixer connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: store.status) { _, status in
                if sessionActive { discovery.stop() }
                if status == .live { dismiss() }
            }
            .onDisappear { discovery.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { discovery.stop() }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Desk.ink)
    }

    private var discoverySection: some View {
        Section {
            if discovery.phase == .scanning {
                HStack {
                    ProgressView().accessibilityHidden(true)
                    Text("Scanning…")
                    Spacer()
                    Button("Stop") { discovery.stop() }
                        .buttonStyle(.borderless).accessibilityLabel("Stop scanning")
                }
                if discovery.total > 0 {
                    ProgressView(value: Double(discovery.checked), total: Double(discovery.total))
                        .accessibilityLabel("Scan progress")
                }
            } else {
                Button {
                    field = nil
                    discovery.start()
                } label: {
                    Label("Scan for mixers", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("scan-mixers")
            }
            ForEach(discovery.mixers) { mixer in
                Button {
                    store.host = mixer.host
                    store.port = String(mixer.port)
                    connect()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mixer.name).font(.headline).lineLimit(2)
                            Text(mixer.host).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Connect to \(mixer.name) at \(mixer.host)")
                .accessibilityIdentifier("discovered-\(mixer.host)")
            }
        } header: {
            Text("Nearby mixers")
        } footer: {
            switch discovery.phase {
            case .failed(let message): Text(message)
            case .stopped: Text("Scan stopped.")
            case .finished where discovery.isPartial:
                Text("Checked the 256-address range around this device. For a mixer elsewhere on this network, enter its address below.")
            case .finished where discovery.mixers.isEmpty:
                Text("No StudioLive mixers replied. Check that the console’s Control port and this device are on the same network.")
            default: EmptyView()
            }
        }
    }

    private func connect() {
        field = nil
        discovery.stop()
        store.connect()
    }

    private var validEndpoint: Bool {
        guard let port = UInt16(store.port), port > 0 else { return false }
        return !store.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var demoActionTitle: String {
        switch store.status {
        case .demo: "Return to mixer"
        case .offline: "Use demo"
        case .connecting: "Cancel and use demo"
        case .live: "Disconnect and use demo"
        }
    }

    private var sessionActive: Bool {
        switch store.status {
        case .live, .connecting: true
        case .demo, .offline: false
        }
    }
}
