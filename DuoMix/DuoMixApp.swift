import SwiftUI

@main
struct DuoMixApp: App {
    @StateObject private var mixer = MixerStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MixerSurface(store: mixer)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { mixer.suspend() }
            if phase == .active { mixer.resume() }
        }
    }
}
