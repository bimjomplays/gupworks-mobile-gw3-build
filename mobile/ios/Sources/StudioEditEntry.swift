import SwiftUI

// The Edit stage's entry point (mockups 15-28 are a181's). When a181's StudioEditView lands, studioEditRoute
// returns `StudioEditRoute(projectId: projectId, videoId: videoId, title: title)` and the video page pushes it on
// MainView's stack; StudioEditStage below is only the stand-in until then and goes with it.

/// a181's Edit page for a video, or nil while it isn't in the app yet
func studioEditRoute(projectId: String, videoId: String, title: String) -> (any Hashable)? { nil }

/// the stand-in shown in the Edit tab until a181's page is there
struct StudioEditStage: View {
    let store: StudioVideoStore

    var body: some View {
        StudioNote(text: "Edit on the PC for now.")
    }
}
