import SwiftUI
import UIKit

// Full-screen pictures in the Photos app's way: pinch zooms where you pinch, drag pans a zoomed picture, double-tap
// zooms to the tapped spot and back, swipe left and right through the chat's pictures, swipe down to close.
// The paging and zooming are UIKit scroll views (one pager of zooming pages); SwiftUI only draws the buttons.

/// One picture in a chat: yours (a message's photos) or Claude's (a reply's pictures and drawings).
struct ChatPhoto: Equatable, Identifiable {
    let id: String
    let link: String
    let mine: Bool
    /// a mockup set's picture: "2b · Cards · Overview" and how its option differs, shown under it
    var title: String? = nil
    var detail: String? = nil
}

/// A chat's pictures, oldest first, as the chat shows them. Ids come from where a picture sits (turn, block,
/// picture), so the tile you tap and the gallery agree even when the same file shows up twice.
enum ChatPhotos {
    /// the prompt bubble's pictures
    static func promptScope(_ turn: String) -> String { "\(turn)/p" }
    /// a block of the turn: a reply's text or a queued message
    static func blockScope(_ turn: String, _ block: Int) -> String { "\(turn)/b\(block)" }
    /// a picture in a bubble
    static func id(scope: String, item: Int) -> String { "\(scope)/\(item)" }
    /// a picture in a reply's media block `slot`
    static func id(scope: String, slot: Int, item: Int) -> String { "\(scope)/m\(slot)/\(item)" }

    /// `briefed`: a thread's first turn, whose prompt (the brief) the task card stands for, so it isn't on screen
    static func collect(turns: [Turn], briefed: String? = nil) -> [ChatPhoto] {
        var out: [ChatPhoto] = []
        for t in turns {
            // these kinds draw no bubble, so their prompt has no pictures on screen
            if !["command", "handoff", "notice", "task"].contains(t.kind) && t.id != briefed {
                let scope = promptScope(t.id)
                for (k, link) in (t.prompt.images ?? []).enumerated() where !link.isEmpty {
                    out.append(ChatPhoto(id: id(scope: scope, item: k), link: link, mine: true))
                }
            }
            for (bi, b) in t.blocks.enumerated() {
                let scope = blockScope(t.id, bi)
                switch b.type {
                case "text":
                    // a mockup set's pictures open among the set's own (MockupSetView), not the chat's
                    for (mi, m) in (b.md ?? []).enumerated() where m.t == "media" && !m.isFallback {
                        for (k, it) in (m.items ?? []).enumerated() where isPicture(it) {
                            out.append(ChatPhoto(id: id(scope: scope, slot: mi, item: k), link: it.url ?? "", mine: false))
                        }
                    }
                case "prompt":
                    for (k, link) in (b.prompt?.images ?? []).enumerated() where !link.isEmpty {
                        out.append(ChatPhoto(id: id(scope: scope, item: k), link: link, mine: true))
                    }
                default:
                    break
                }
            }
        }
        return out
    }

    /// pictures and drawings; videos (and their posters) play in the video player instead
    static func isPicture(_ it: MDItem) -> Bool {
        it.kind != "video" && !(it.url ?? "").isEmpty
    }
}

/// The open chat's pictures, for the viewer: what the chat has now, and its older pages.
struct PhotoSource {
    var photos: @MainActor () -> [ChatPhoto]
    var more: @MainActor () -> Bool
    var loadOlder: @MainActor () async -> Void
}

extension EnvironmentValues {
    /// set by ChatView; nil outside a chat (a note's pictures open one at a time)
    @Entry var chatPhotos: PhotoSource? = nil
    /// where the pictures below sit in the chat (ChatPhotos.promptScope / blockScope); nil: not in a turn
    @Entry var photoScope: String? = nil
}

/// What a tap opens full screen: a video, or a picture with the chat's other pictures to swipe through.
struct MediaOpen: Identifiable {
    let item: MDItem
    var photos: [ChatPhoto] = []
    var start = ""
    var id: String { start.isEmpty ? item.id : start }

    /// a tapped picture: the chat's pictures when this one is among them, else just this one
    @MainActor
    static func picture(_ item: MDItem, id: String?, source: PhotoSource?) -> MediaOpen {
        if let id, let source {
            let all = source.photos()
            if all.contains(where: { $0.id == id }) { return MediaOpen(item: item, photos: all, start: id) }
        }
        let one = ChatPhoto(id: "only", link: item.url ?? "", mine: false)
        return MediaOpen(item: item, photos: [one], start: one.id)
    }
}

/// The sums behind zooming, kept apart so tests can check them.
enum PhotoZoom {
    static let doubleTap: CGFloat = 2.5

    /// a picture's size scaled to fit inside `box`
    static func fit(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return box }
        let s = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * s, height: image.height * s)
    }

    /// insets that keep content smaller than the box in its middle
    static func inset(content: CGSize, box: CGSize) -> UIEdgeInsets {
        let x = max(0, (box.width - content.width) / 2)
        let y = max(0, (box.height - content.height) / 2)
        return UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    /// where to scroll so `point` (in the picture at fit size) comes to the screen's middle at `scale`, kept inside
    /// the picture's edges
    static func offset(scale: CGFloat, point: CGPoint, fit: CGSize, box: CGSize) -> CGPoint {
        let content = CGSize(width: fit.width * scale, height: fit.height * scale)
        let ins = inset(content: content, box: box)
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), max(lo, hi)) }
        return CGPoint(x: clamp(point.x * scale - box.width / 2, -ins.left, content.width - box.width + ins.right),
                       y: clamp(point.y * scale - box.height / 2, -ins.top, content.height - box.height + ins.bottom))
    }

    /// how far a picture zooms: 3× at least, up to twice its own pixels (8× at most)
    static func maxScale(pixels: CGSize, fit: CGSize, screenScale: CGFloat) -> CGFloat {
        guard fit.width > 0, screenScale > 0 else { return 3 }
        let native = pixels.width / (fit.width * screenScale)
        return min(8, max(3, native * 2))
    }
}

/// Full screen: the pictures, and over them close, "3 of 12" and share (a tap hides them).
struct PhotoViewer: View {
    let base: URL?
    let source: PhotoSource?
    @State private var photos: [ChatPhoto]
    @State private var current: String
    @State private var chrome = true
    @State private var dragging = false
    @State private var older = false
    @Environment(\.dismiss) private var dismiss

    init(photos: [ChatPhoto], start: String, base: URL?, source: PhotoSource?) {
        self.base = base
        self.source = source
        _photos = State(initialValue: photos)
        _current = State(initialValue: start)
    }

    private var index: Int { photos.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        ZStack(alignment: .top) {
            PhotoPager(ids: photos.map(\.id),
                       urls: photos.map { MediaLink.url($0.link, base: base) },
                       index: index,
                       onIndex: { i in
                           guard photos.indices.contains(i) else { return }
                           current = photos[i].id
                           olderIfFirst()
                       },
                       onTap: { withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() } },
                       onDrag: { d in withAnimation(.easeInOut(duration: 0.15)) { dragging = d } },
                       onClose: {
                           // the pager already slid the picture away; no second slide
                           var t = Transaction()
                           t.disablesAnimations = true
                           withTransaction(t) { dismiss() }
                       })
                .ignoresSafeArea()
            if chrome && !dragging {
                bar.transition(.opacity)
                caption.transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoViewer")
        .statusBarHidden(!chrome || dragging)
        .persistentSystemOverlays(chrome ? .automatic : .hidden)
        .presentationBackground(.clear)
        .onAppear { olderIfFirst() }
    }

    private var bar: some View {
        HStack {
            glassButton("xmark", "Close", id: "photoClose") { dismiss() }
            Spacer()
            if photos.count > 1 {
                Text("\(index + 1) of \(photos.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(in: .capsule)
                    .accessibilityIdentifier("photoCounter")
            }
            Spacer()
            glassButton("square.and.arrow.up", "Share", id: "photoShare") { share() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// a mockup set's picture says which one it is: "2b · Cards · Overview" and how the option differs
    @ViewBuilder
    private var caption: some View {
        if photos.indices.contains(index), let title = photos[index].title {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("photoTitle")
                if let d = photos[index].detail, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func glassButton(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// at the first picture: the chat's older pages, until one brings more pictures (the place stays put)
    @MainActor
    private func olderIfFirst() {
        guard index == 0, !older, let source, source.more() else { return }
        older = true
        Task { @MainActor in
            var tries = 0
            while source.more(), tries < 5 {
                tries += 1
                let before = photos.count
                await source.loadOlder()
                let now = source.photos()
                if now.contains(where: { $0.id == current }) { photos = now }
                if photos.count > before { break }
            }
            older = false
        }
    }

    @MainActor
    private func share() {
        guard photos.indices.contains(index), let url = MediaLink.url(photos[index].link, base: base) else { return }
        Task { @MainActor in
            guard let image = await ImageCache.shared.load(url) else { return }
            ShareSheet.present([image])
        }
    }
}

/// The system share sheet over whatever is on screen (here: the viewer).
@MainActor
enum ShareSheet {
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
              var top = window.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

private struct PhotoPager: UIViewRepresentable {
    let ids: [String]
    let urls: [URL?]
    let index: Int
    let onIndex: (Int) -> Void
    let onTap: () -> Void
    let onDrag: (Bool) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> PhotoPagerView {
        PhotoPagerView(frame: .zero)
    }

    func updateUIView(_ view: PhotoPagerView, context: Context) {
        view.onIndex = onIndex
        view.onTap = onTap
        view.onDrag = onDrag
        view.onClose = onClose
        view.set(ids: ids, urls: urls, index: index)
    }
}

/// Lets the swipe-down start only on a picture at its fit size, and only for a mostly downward drag.
@MainActor
private final class PanGate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: (UIGestureRecognizer) -> Bool = { _ in true }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin(gestureRecognizer)
    }
}

/// The pager: pages side by side with a gap between them, only the shown one and its neighbours alive.
/// For tests it is one accessibility element, "photoPage", whose value says whether the shown picture is zoomed.
final class PhotoPagerView: UIView, UIScrollViewDelegate {
    var onIndex: ((Int) -> Void)?
    var onTap: (() -> Void)?
    var onDrag: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    private let pager = UIScrollView()
    private let gap: CGFloat = 20
    private var ids: [String] = []
    private var urls: [URL?] = []
    private(set) var index = 0
    private var pages: [Int: PhotoPage] = [:]
    private var spare: [PhotoPage] = []
    private var laidOut: CGSize = .zero
    private var applying = false
    private let dismissPan = UIPanGestureRecognizer()
    private let gate = PanGate()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.alwaysBounceVertical = false
        pager.backgroundColor = .clear
        pager.delegate = self
        addSubview(pager)

        dismissPan.addTarget(self, action: #selector(dragged(_:)))
        dismissPan.maximumNumberOfTouches = 1
        gate.shouldBegin = { [weak self] g in self?.mayDismiss(g) ?? false }
        dismissPan.delegate = gate
        addGestureRecognizer(dismissPan)
        // sideways swipes wait until it is clear the drag isn't a swipe down
        pager.panGestureRecognizer.require(toFail: dismissPan)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        single.require(toFail: double)
        addGestureRecognizer(single)

        isAccessibilityElement = true
        accessibilityIdentifier = "photoPage"
        accessibilityLabel = "Picture"
        accessibilityTraits = .image
        accessibilityValue = "fit"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(ids: [String], urls: [URL?], index: Int) {
        let i = urls.isEmpty ? 0 : min(max(0, index), urls.count - 1)
        guard ids != self.ids || i != self.index else { return }
        if ids != self.ids {
            for p in pages.values { recycle(p) }
            pages = [:]
        }
        self.ids = ids
        self.urls = urls
        self.index = i
        layoutPages()
        tile()
        refreshValue()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        layoutPages()
        tile()
    }

    private var pageWidth: CGFloat { bounds.width + gap }

    private func pageFrame(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i) * pageWidth + gap / 2, y: 0, width: bounds.width, height: bounds.height)
    }

    /// the pager a gap wider than the screen, so the gap scrolls past between pictures
    private func layoutPages() {
        guard bounds.width > 0 else { return }
        applying = true
        pager.frame = CGRect(x: -gap / 2, y: 0, width: pageWidth, height: bounds.height)
        pager.contentSize = CGSize(width: pageWidth * CGFloat(urls.count), height: bounds.height)
        for (i, p) in pages { p.frame = pageFrame(i) }
        pager.contentOffset = CGPoint(x: CGFloat(index) * pageWidth, y: 0)
        applying = false
    }

    /// pages for the shown picture and its neighbours; the rest go back to the spare pile
    private func tile() {
        guard bounds.width > 0, !urls.isEmpty else { return }
        let want = Set(max(0, index - 1)...min(urls.count - 1, index + 1))
        for i in Array(pages.keys) where !want.contains(i) {
            if let p = pages[i] { recycle(p) }
            pages[i] = nil
        }
        for i in want.sorted() where pages[i] == nil {
            let p = spare.popLast() ?? makePage()
            p.frame = pageFrame(i)
            pager.addSubview(p)
            p.load(urls[i])
            pages[i] = p
        }
    }

    private func makePage() -> PhotoPage {
        let p = PhotoPage(frame: .zero)
        // a zoomed picture pans first; at fit size a downward drag closes instead
        p.panGestureRecognizer.require(toFail: dismissPan)
        p.onZoom = { [weak self] in self?.refreshValue() }
        return p
    }

    private func recycle(_ p: PhotoPage) {
        p.removeFromSuperview()
        p.transform = .identity
        p.clear()
        spare.append(p)
    }

    private func refreshValue() {
        accessibilityValue = (pages[index]?.isZoomed ?? false) ? "zoomed" : "fit"
    }

    // MARK: paging

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !applying, pageWidth > 0, !urls.isEmpty else { return }
        let i = min(max(0, Int((scrollView.contentOffset.x / pageWidth).rounded())), urls.count - 1)
        guard i != index else { return }
        index = i
        tile()
        refreshValue()
        onIndex?(i)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // a picture swiped away is back at its fit size when you return to it
        for (i, p) in pages where i != index && p.isZoomed { p.fitImage() }
        refreshValue()
    }

    // MARK: taps

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTap?()
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        guard let p = pages[index] else { return }
        p.toggleZoom(at: g.location(in: p.imageView))
    }

    // MARK: swipe down to close

    private func mayDismiss(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, !(pages[index]?.isZoomed ?? false) else { return false }
        let v = pan.velocity(in: self)
        return v.y > 0 && abs(v.y) > abs(v.x) * 1.2
    }

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        let page = pages[index]
        let progress = min(1, max(0, t.y) / max(1, bounds.height * 0.5))
        switch g.state {
        case .began:
            onDrag?(true)
        case .changed:
            let s = 1 - 0.25 * progress
            page?.transform = CGAffineTransform(translationX: t.x, y: t.y).scaledBy(x: s, y: s)
            backgroundColor = UIColor.black.withAlphaComponent(1 - progress)
        case .ended, .cancelled, .failed:
            let v = g.velocity(in: self)
            if g.state == .ended, t.y > 110 || v.y > 900 {
                isUserInteractionEnabled = false
                let down = bounds.height
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                    page?.transform = CGAffineTransform(translationX: t.x, y: down).scaledBy(x: 0.7, y: 0.7)
                    self.backgroundColor = .clear
                }, completion: { _ in
                    self.onClose?()
                })
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                    page?.transform = .identity
                    self.backgroundColor = .black
                })
                onDrag?(false)
            }
        default:
            break
        }
    }
}

/// One page: a picture in its own zooming scroll view, kept in the middle while smaller than the screen.
final class PhotoPage: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onZoom: (() -> Void)?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let broken = UIImageView(image: UIImage(systemName: "photo.badge.exclamationmark"))
    private var url: URL?
    private var task: Task<Void, Never>?
    private var laidOut: CGSize = .zero

    var isZoomed: Bool { zoomScale > minimumZoomScale + 0.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true
        minimumZoomScale = 1
        maximumZoomScale = 1
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        broken.tintColor = UIColor(white: 1, alpha: 0.5)
        broken.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        broken.isHidden = true
        broken.sizeToFit()
        addSubview(broken)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func load(_ url: URL?) {
        clear()
        self.url = url
        guard let url else {
            broken.isHidden = false
            return
        }
        if let img = ImageCache.shared.cached(url) {
            show(img)
            return
        }
        spinner.startAnimating()
        task = Task { @MainActor [weak self] in
            let img = await ImageCache.shared.load(url)
            guard let self, !Task.isCancelled, self.url == url else { return }
            self.spinner.stopAnimating()
            if let img { self.show(img) } else { self.broken.isHidden = false }
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        url = nil
        spinner.stopAnimating()
        broken.isHidden = true
        imageView.image = nil
        fitImage()
    }

    private func show(_ img: UIImage) {
        imageView.image = img
        fitImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        spinner.center = middle
        broken.center = middle
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        fitImage()
    }

    /// back to fit size, in the middle
    func fitImage() {
        minimumZoomScale = 1
        zoomScale = 1
        let box = bounds.size
        guard box.width > 0, box.height > 0 else { return }
        let size = imageView.image?.size ?? box
        let fit = PhotoZoom.fit(size, in: box)
        imageView.frame = CGRect(origin: .zero, size: fit)
        contentSize = fit
        if let img = imageView.image {
            let pixels = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
            maximumZoomScale = PhotoZoom.maxScale(pixels: pixels, fit: fit, screenScale: traitCollection.displayScale)
        } else {
            maximumZoomScale = 1
        }
        contentInset = PhotoZoom.inset(content: fit, box: box)
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        onZoom?()
    }

    /// double-tap: zoom in on `point` (in the picture at fit size), or back out
    func toggleZoom(at point: CGPoint) {
        guard imageView.image != nil else { return }
        let fit = imageView.bounds.size
        if isZoomed {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
                self.zoomScale = self.minimumZoomScale
                self.contentInset = PhotoZoom.inset(content: fit, box: self.bounds.size)
                self.contentOffset = CGPoint(x: -self.contentInset.left, y: -self.contentInset.top)
            }, completion: { _ in
                self.onZoom?()
            })
            return
        }
        let p = CGPoint(x: min(max(0, point.x), fit.width), y: min(max(0, point.y), fit.height))
        let scale = min(PhotoZoom.doubleTap, maximumZoomScale)
        let target = PhotoZoom.offset(scale: scale, point: p, fit: fit, box: bounds.size)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.zoomScale = scale
            self.contentInset = PhotoZoom.inset(content: self.contentSize, box: self.bounds.size)
            self.contentOffset = target
        }, completion: { _ in
            self.onZoom?()
        })
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        contentInset = PhotoZoom.inset(content: contentSize, box: bounds.size)
        onZoom?()
    }
}
