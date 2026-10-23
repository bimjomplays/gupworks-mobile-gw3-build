import AVKit
import SwiftUI
import UIKit

// Pictures and videos in a chat. Links are the PC's signed /v1/media/… links (no token needed, they expire after a
// while) or, in the demo, files in the app.

/// Loads and keeps pictures for the session (memory only; nothing is written to the phone's storage).
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        var img: UIImage?
        if url.isFileURL {
            img = UIImage(contentsOfFile: url.path)
        } else if let got = try? await session.data(from: url), (got.1 as? HTTPURLResponse)?.statusCode == 200 {
            img = UIImage(data: got.0)
        }
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// A picture from a link: grey while it loads, a broken-picture mark when it can't.
struct RemoteImage: View {
    let url: URL?
    let fill: Bool
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, fill: Bool = false) {
        self.url = url
        self.fill = fill
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Rectangle().fill(ChatStyle.cardBG)
                if failed {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(ChatStyle.dim)
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            image = ImageCache.shared.cached(url)
            if image == nil {
                image = await ImageCache.shared.load(url)
                failed = image == nil
            }
        }
    }
}

/// A reply's pictures and videos: one fills the column; several sit in a two-column grid. Tap for full screen.
struct MediaGroup: View {
    let items: [MDItem]
    let base: URL?
    @State private var open: MDItem?

    init(items: [MDItem], base: URL?) {
        self.items = items
        self.base = base
    }

    var body: some View {
        Group {
            if items.count == 1, let it = items.first {
                tile(it, single: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        tile(it, single: false)
                    }
                }
            }
        }
        .fullScreenCover(item: $open) { it in
            MediaViewer(item: it, base: base)
        }
    }

    @ViewBuilder
    private func tile(_ it: MDItem, single: Bool) -> some View {
        let isVideo = it.kind == "video"
        let picture = MediaLink.url(isVideo ? it.poster : it.url, base: base)
        Button { open = it } label: {
            ZStack {
                if single {
                    RemoteImage(url: picture)
                        .frame(maxWidth: .infinity, maxHeight: 360)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RemoteImage(url: picture, fill: true))
                }
                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isVideo ? "Video \(it.name ?? "")" : "Picture \(it.name ?? "")")
        .accessibilityIdentifier(isVideo ? "video" : "picture")
    }
}

extension MDItem: Identifiable {
    var id: String { (url ?? "") + (name ?? "") }
}

/// Full screen: a picture you can pinch, or a video playing in the system player.
struct MediaViewer: View {
    let item: MDItem
    let base: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var scale: CGFloat = 1

    init(item: MDItem, base: URL?) {
        self.item = item
        self.base = base
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if item.kind == "video" {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        if player == nil, let url = MediaLink.url(item.url, base: base) {
                            let p = AVPlayer(url: url)
                            player = p
                            p.play()
                        }
                    }
                    .onDisappear { player?.pause() }
            } else {
                RemoteImage(url: MediaLink.url(item.url, base: base))
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture()
                        .onChanged { scale = max(1, min(5, $0.magnification)) }
                        .onEnded { _ in withAnimation { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .padding(16)
            .accessibilityLabel("Close")
        }
    }
}
