import SwiftUI

/// The Edit stage of a Studio video (mockups 15-28). a181 builds the real one in its own files and replaces
/// this view; the video page shows it when the Edit tab is open.
struct StudioEditStage: View {
    let store: StudioVideoStore

    var body: some View {
        VStack(spacing: 10) {
            LucideIcon(name: "scissors", size: 28)
                .foregroundStyle(Theme.secondary)
            Text("Edit on the PC for now")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.title)
            Text("The phone's timeline editor is coming.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
