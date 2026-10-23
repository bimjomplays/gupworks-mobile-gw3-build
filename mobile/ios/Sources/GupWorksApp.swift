import SwiftUI

@main
struct GupWorksApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
        }
    }
}

/// Not paired: the pairing screen. Paired: the chats list, refreshed whenever the app comes to the front.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if model.isPaired {
                ChatsListView()
            } else {
                PairingView()
            }
        }
        .animation(.default, value: model.isPaired)
        .onChange(of: phase) { _, now in
            if now == .active { Task { await model.refresh() } }
        }
        .task(id: model.isPaired) { await model.refresh() }
        .onOpenURL { url in
            // only the pairing screen takes links; once paired, unpair first in Settings
            if !model.isPaired { model.incomingLink = url.absoluteString }
        }
    }
}
