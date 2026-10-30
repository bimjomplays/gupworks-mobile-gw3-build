import SwiftUI

// The Edit stage's entry point: the video page pushes this route on MainView's stack (a180 → a181).

/// a181's Edit page for a video
func studioEditRoute(projectId: String, videoId: String, title: String) -> (any Hashable)? {
    StudioEditRoute(projectId: projectId, videoId: videoId, title: title)
}
