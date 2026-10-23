import SwiftUI

@main
struct GupWorksApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                // as the unit tests' host the app shows nothing (no camera prompt left behind for the UI tests)
                if NSClassFromString("XCTestCase") != nil { Color.clear } else { RootView() }
            }
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
        }
    }
}

/// Not paired: the pairing screen. Paired: the chats list, live while the app is in front.
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
        // in front: load the list, then follow the PC's changes until the app goes to the back
        .task(id: [model.isPaired, phase == .active]) {
            guard phase == .active else { return }
            await model.refresh()
            await model.followHome()
        }
        .onOpenURL { url in
            // only the pairing screen takes links; once paired, unpair first in Settings
            if !model.isPaired { model.incomingLink = url.absoluteString }
        }
    }
}
