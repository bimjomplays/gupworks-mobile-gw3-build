import SwiftUI

@main
struct GupWorksApp: App {
    @State private var model = AppModel()
    // the video player may turn sideways; everything else stays upright (Orientation in VideoPlayer.swift)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

/// Not paired: the pairing screen. Paired: a new chat with the menu beside it (5a), live while the app is in front.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if model.isPaired {
                MainView()
            } else {
                PairingView()
            }
        }
        .animation(.default, value: model.isPaired)
        // in front: load the list, then follow the PC's changes until the app goes to the back
        .task(id: [model.isPaired, phase == .active]) {
            guard phase == .active else { return }
            if model.isPaired { model.transfer.pump() }  // files left waiting go on up (a144)
            await model.refresh()
            await model.followHome()
        }
        .onChange(of: phase) { _, now in
            if model.isPaired { model.transfer.active = now == .active }
        }
        .onOpenURL { url in
            // only the pairing screen takes links; once paired, unpair first in Settings
            if !model.isPaired { model.incomingLink = url.absoluteString }
        }
    }
}
