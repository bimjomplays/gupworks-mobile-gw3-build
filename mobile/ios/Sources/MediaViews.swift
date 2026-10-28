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

/// Your photos in a message: square tiles in rows of two to four (four and nine make square blocks), right-aligned,
/// wrapping onto more rows. Never wider than the width it's offered: one long row of 96 pt tiles once made the
/// whole chat wider than the screen and pushed the box and its send button off it.
struct PhotoGrid: Layout {
    var tile: CGFloat = 96
    var spacing: CGFloat = 6
    /// rows hug the left edge instead (the PC's side of the file transfer chat)
    var leading = false

    struct Shape: Equatable {
        var columns: Int
        var rows: Int
        var side: CGFloat
    }

    /// how `count` tiles sit in `width` (nil: as wide as they like)
    static func shape(count: Int, width: CGFloat?, tile: CGFloat = 96, spacing: CGFloat = 6) -> Shape {
        guard count > 0 else { return Shape(columns: 0, rows: 0, side: 0) }
        var columns = count <= 9 ? [1, 2, 3, 2, 3, 3, 4, 4, 3][count - 1] : 4
        guard let width, width.isFinite else {
            return Shape(columns: columns, rows: (count + columns - 1) / columns, side: tile)
        }
        // fewer, bigger tiles rather than tiny ones on a narrow screen
        while columns > 1, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns) < 56 { columns -= 1 }
        let side = max(1, min(tile, ((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)))
        return Shape(columns: columns, rows: (count + columns - 1) / columns, side: side)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = Self.shape(count: subviews.count, width: proposal.width, tile: tile, spacing: spacing)
        guard s.columns > 0 else { return .zero }
        return CGSize(width: CGFloat(s.columns) * s.side + CGFloat(s.columns - 1) * spacing,
                      height: CGFloat(s.rows) * s.side + CGFloat(s.rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = Self.shape(count: subviews.count, width: bounds.width, tile: tile, spacing: spacing)
        guard s.columns > 0 else { return }
        let size = ProposedViewSize(width: s.side, height: s.side)
        for (i, view) in subviews.enumerated() {
            let row = i / s.columns, col = i % s.columns
            let inRow = min(s.columns, subviews.count - row * s.columns)
            // each row hugs the right edge, like the bubble under it (the left one when `leading`)
            let rowWidth = CGFloat(inRow) * s.side + CGFloat(inRow - 1) * spacing
            let x = (leading ? bounds.minX : bounds.maxX - rowWidth) + CGFloat(col) * (s.side + spacing)
            let y = bounds.minY + CGFloat(row) * (s.side + spacing)
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: size)
        }
    }
}

/// One square tile of a PhotoGrid: takes exactly the room it's given and crops the picture into it.
struct PhotoTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
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

/// A reply's pictures and videos: one fills the column; several sit in a two-column grid. Tap for full screen;
/// a picture opens among the chat's other pictures when it sits in a chat (`slot`: its block in the reply).
/// Audio files play in their own cards under them, as wide as the column (AudioPlayer.swift).
struct MediaGroup: View {
    let items: [MDItem]
    let base: URL?
    let slot: Int?
    @Environment(\.chatPhotos) private var photos
    @Environment(\.photoScope) private var scope
    @State private var open: MediaOpen?

    init(items: [MDItem], base: URL?, slot: Int? = nil) {
        self.items = items
        self.base = base
        self.slot = slot
    }

    var body: some View {
        // an item keeps its place in the block (`k`): the photo viewer names pictures by it (ChatPhotos.collect)
        let visual = Array(items.enumerated()).filter { $0.element.kind != "audio" }
        let sounds = items.filter { $0.kind == "audio" }
        VStack(alignment: .leading, spacing: 8) {
            if visual.count == 1, let one = visual.first {
                tile(one.element, at: one.offset, single: true)
            } else if !visual.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(visual, id: \.offset) { k, it in
                        tile(it, at: k, single: false)
                    }
                }
            }
            if !sounds.isEmpty {
                AudioList(items: sounds, base: base)
            }
        }
        .fullScreenCover(item: $open) { o in
            MediaViewer(open: o, base: base, source: photos)
        }
    }

    private func tap(_ it: MDItem, at k: Int) {
        if it.kind == "video" {
            open = MediaOpen(item: it)
            return
        }
        var id: String?
        if let scope, let slot { id = ChatPhotos.id(scope: scope, slot: slot, item: k) }
        open = MediaOpen.picture(it, id: id, source: photos)
    }

    @ViewBuilder
    private func tile(_ it: MDItem, at k: Int, single: Bool) -> some View {
        let isVideo = it.kind == "video"
        let picture = MediaLink.url(isVideo ? it.poster : it.url, base: base)
        Button { tap(it, at: k) } label: {
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

/// Full screen: a video in the video player, or pictures in the photo viewer.
struct MediaViewer: View {
    let open: MediaOpen
    let base: URL?
    var source: PhotoSource? = nil

    init(open: MediaOpen, base: URL?, source: PhotoSource? = nil) {
        self.open = open
        self.base = base
        self.source = source
    }

    /// one item on its own, outside a chat (the project Library's videos)
    init(item: MDItem, base: URL?) {
        let one = ChatPhoto(id: "only", link: item.url ?? "", mine: false)
        self.init(open: item.kind == "video" ? MediaOpen(item: item) : MediaOpen(item: item, photos: [one], start: one.id),
                  base: base)
    }

    var body: some View {
        if open.item.kind == "video" {
            VideoPlayerScreen(item: open.item, base: base)
        } else {
            PhotoViewer(photos: open.photos, start: open.start, base: base, source: source)
        }
    }
}
