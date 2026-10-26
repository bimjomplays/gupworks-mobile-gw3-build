import UIKit
import XCTest
@testable import GupWorks3

/// The photo viewer's gallery (every picture in a chat, in order) and its zoom sums.
final class PhotoViewerTests: XCTestCase {
    private func turn(_ id: String, kind: String = "prompt", images: [String]? = nil, blocks: String = "[]") -> String {
        let imgs = images.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
        return """
        {"id":"\(id)","kind":"\(kind)","start":0,"state":"done","prompt":{"text":"hi","images":\(imgs)},
         "open":true,"blocks":\(blocks),"rev":"1"}
        """
    }

    private func turns(_ parts: [String]) throws -> [Turn] {
        try JSONDecoder().decode([Turn].self, from: Data(("[" + parts.joined(separator: ",") + "]").utf8))
    }

    private let reply = """
    [{"type":"card","id":"c1","title":"Read","state":"done"},
     {"type":"text","answer":true,"md":[
        {"t":"p","text":"Here they are"},
        {"t":"media","items":[{"kind":"image","url":"/v1/media/a.png","name":"a.png"},
                              {"kind":"video","url":"/v1/media/v.mp4","name":"v.mp4","poster":"/v1/media/v.jpg"},
                              {"kind":"image","url":"/v1/media/b.png","name":"b.png"}]},
        {"t":"p","text":"and a drawing"},
        {"t":"media","items":[{"kind":"image","url":"/v1/media/d.svg.png","name":"drawing"}]}]}]
    """

    func testYoursAndClaudesInChatOrder() throws {
        let t = try turns([
            turn("t1", images: ["/v1/media/u1.jpg"], blocks: reply),
            turn("t2", images: ["/v1/media/u2.jpg", "/v1/media/u3.jpg"]),
        ])
        let photos = ChatPhotos.collect(turns: t)
        XCTAssertEqual(photos.map(\.link), ["/v1/media/u1.jpg", "/v1/media/a.png", "/v1/media/b.png",
                                            "/v1/media/d.svg.png", "/v1/media/u2.jpg", "/v1/media/u3.jpg"])
        XCTAssertEqual(photos.map(\.mine), [true, false, false, false, true, true])
    }

    func testVideosAndTheirPostersAreLeftOut() throws {
        let photos = ChatPhotos.collect(turns: try turns([turn("t1", blocks: reply)]))
        XCTAssertFalse(photos.contains { $0.link.hasSuffix(".mp4") || $0.link.hasSuffix("v.jpg") })
        XCTAssertEqual(photos.count, 3)
    }

    func testIdsMatchWhereTheTileSits() throws {
        // the same file twice still gives two places, and the ids are the ones the tiles build
        let t = try turns([turn("t1", images: ["/v1/media/x.jpg", "/v1/media/x.jpg"], blocks: reply)])
        let ids = ChatPhotos.collect(turns: t).map(\.id)
        XCTAssertEqual(ids, [
            ChatPhotos.id(scope: ChatPhotos.promptScope("t1"), item: 0),
            ChatPhotos.id(scope: ChatPhotos.promptScope("t1"), item: 1),
            ChatPhotos.id(scope: ChatPhotos.blockScope("t1", 1), slot: 1, item: 0),
            ChatPhotos.id(scope: ChatPhotos.blockScope("t1", 1), slot: 1, item: 2),
            ChatPhotos.id(scope: ChatPhotos.blockScope("t1", 1), slot: 3, item: 0),
        ])
        XCTAssertEqual(Set(ids).count, ids.count, "every picture has its own id")
        // the same chat read again (a refresh) gives the same ids
        XCTAssertEqual(ChatPhotos.collect(turns: t).map(\.id), ids)
    }

    func testQueuedMessagesAndNoBubbleKinds() throws {
        let queued = #"[{"type":"prompt","prompt":{"text":"later","images":["/v1/media/q.jpg"]}}]"#
        let t = try turns([
            turn("t1", kind: "command", images: ["/v1/media/hidden.jpg"]),
            turn("t2", images: nil, blocks: queued),
        ])
        let photos = ChatPhotos.collect(turns: t)
        XCTAssertEqual(photos.map(\.link), ["/v1/media/q.jpg"], "a command draws no bubble; a queued message does")
        XCTAssertEqual(photos.first?.id, ChatPhotos.id(scope: ChatPhotos.blockScope("t2", 0), item: 0))
    }

    @MainActor
    func testOpeningAPictureOutsideTheChatShowsJustIt() {
        let item = MDItem(kind: "image", url: "/v1/media/n.png", name: "n.png")
        let one = MediaOpen.picture(item, id: nil, source: nil)
        XCTAssertEqual(one.photos.map(\.link), ["/v1/media/n.png"])
        XCTAssertEqual(one.start, one.photos.first?.id)
        let gallery = [ChatPhoto(id: "a", link: "/v1/media/a.png", mine: true),
                       ChatPhoto(id: "b", link: "/v1/media/n.png", mine: false)]
        let source = PhotoSource(photos: { gallery }, more: { false }, loadOlder: {})
        let open = MediaOpen.picture(item, id: "b", source: source)
        XCTAssertEqual(open.photos, gallery)
        XCTAssertEqual(open.start, "b")
        XCTAssertEqual(MediaOpen.picture(item, id: "gone", source: source).photos.count, 1, "not in the chat: alone")
    }

    // MARK: zoom sums

    func testFit() {
        let box = CGSize(width: 400, height: 800)
        XCTAssertEqual(PhotoZoom.fit(CGSize(width: 2000, height: 1000), in: box), CGSize(width: 400, height: 200))
        XCTAssertEqual(PhotoZoom.fit(CGSize(width: 100, height: 400), in: box), CGSize(width: 200, height: 800))
        XCTAssertEqual(PhotoZoom.fit(.zero, in: box), box)
    }

    func testInsetCentresSmallContent() {
        let box = CGSize(width: 400, height: 800)
        let i = PhotoZoom.inset(content: CGSize(width: 400, height: 200), box: box)
        XCTAssertEqual(i, UIEdgeInsets(top: 300, left: 0, bottom: 300, right: 0))
        XCTAssertEqual(PhotoZoom.inset(content: CGSize(width: 1000, height: 1000), box: box), .zero)
    }

    func testDoubleTapBringsTheTappedSpotToTheMiddle() {
        let box = CGSize(width: 400, height: 800)
        let fit = CGSize(width: 400, height: 800)
        // a spot near the middle: centred exactly
        let o = PhotoZoom.offset(scale: 2, point: CGPoint(x: 150, y: 300), fit: fit, box: box)
        XCTAssertEqual(o, CGPoint(x: 100, y: 200))
        // the top-left corner: as far as the picture goes, never past its edge
        XCTAssertEqual(PhotoZoom.offset(scale: 2, point: .zero, fit: fit, box: box), .zero)
        // the bottom-right corner: the far edges
        XCTAssertEqual(PhotoZoom.offset(scale: 2, point: CGPoint(x: 400, y: 800), fit: fit, box: box),
                       CGPoint(x: 400, y: 800))
    }

    func testDoubleTapOnAWidePicture() {
        // 400 × 200 in a 400 × 800 screen at 2×: 800 × 400, still shorter than the screen, so it stays centred
        // up and down (offset −200 = the inset) while left and right follow the tap
        let box = CGSize(width: 400, height: 800)
        let fit = CGSize(width: 400, height: 200)
        let o = PhotoZoom.offset(scale: 2, point: CGPoint(x: 300, y: 50), fit: fit, box: box)
        XCTAssertEqual(o, CGPoint(x: 400, y: -200))
        let i = PhotoZoom.offset(scale: 2, point: CGPoint(x: 200, y: 100), fit: fit, box: box)
        XCTAssertEqual(i, CGPoint(x: 200, y: -200))
    }

    func testMaxScale() {
        // a picture with the screen's own pixels: 3×; a big photo: up to twice its pixels, 8× at most
        XCTAssertEqual(PhotoZoom.maxScale(pixels: CGSize(width: 1200, height: 900), fit: CGSize(width: 400, height: 300),
                                          screenScale: 3), 3)
        XCTAssertEqual(PhotoZoom.maxScale(pixels: CGSize(width: 4800, height: 3600), fit: CGSize(width: 400, height: 300),
                                          screenScale: 3), 8)
        XCTAssertEqual(PhotoZoom.maxScale(pixels: CGSize(width: 2400, height: 1800), fit: CGSize(width: 400, height: 300),
                                          screenScale: 3), 4)
    }
}
