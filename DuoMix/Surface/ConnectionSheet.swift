import SwiftUI

struct ConnectionSheet: View {
    @ObservedObject var store: MixerStore
    @Environment(\.dismiss) private var dismiss
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
                        Text("The faders control a local practice mix.").foregroundStyle(.secondary)
                    case .connecting:
                        Text("Waiting for the console to send its channel state.").foregroundStyle(.secondary)
                    case .live:
                        Text(store.hasPendingWrites
                             ? "Faders show your requested settings while the desk confirms them."
                             : "The faders control the connected console.")
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
                    Text("PreSonus · Series III")
                } footer: {
                    Text("Connect the mixer’s Control Ethernet port to the router. Join its Wi-Fi and enter the mixer’s control address.")
                }
                .disabled(sessionActive)
                Section {
                    switch store.status {
                    case .connecting:
                        Button("Cancel connection") { field = nil; store.disconnect() }
                    case .live:
                        Button("Disconnect") { store.disconnect() }
                    case .demo, .offline:
                        Button("Connect to mixer") { field = nil; store.connect() }
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
            .onChange(of: store.status.displayName) { _, status in
                if status == "Live" { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Desk.mint)
    }

    private var validEndpoint: Bool {
        guard let port = UInt16(store.port), port > 0 else { return false }
        return !store.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var demoActionTitle: String {
        switch store.status {
        case .demo: "Return to demo desk"
        case .offline: "Open demo desk"
        case .connecting: "Cancel and open demo desk"
        case .live: "Disconnect and open demo desk"
        }
    }

    private var sessionActive: Bool {
        switch store.status {
        case .live, .connecting: true
        case .demo, .offline: false
        }
    }
}
