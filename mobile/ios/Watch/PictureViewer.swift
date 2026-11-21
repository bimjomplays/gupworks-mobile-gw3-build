import SwiftUI

/// A picture on the whole screen (round 2 screen 7): the crown zooms, a drag looks around, Before | After flips in
/// place, the caption from the ask on top, ✕ back to the card.
struct PictureViewer: View {
    @Environment(WatchStore.self) private var store
    let open: PictureOpen
    @State private var index = 0
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var panStart = CGSize.zero
    @State private var started = false

    var body: some View {
        let pictures = (store.card(open.key) ?? store.item(open.key).map(WatchCard.init))?.pictures ?? []
        let pic = pictures.indices.contains(index) ? pictures[index] : nil
        let _ = store.picturesChanged
        GeometryReader { geo in
            ZStack {
                Color.black
                if let pic, let img = store.image(pic.url) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom)
                        .offset(pan)
                        .clipped()
                        .accessibilityIdentifier("watchPictureFull")
                } else {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in
                    pan = clamp(CGSize(width: panStart.width + g.translation.width,
                                       height: panStart.height + g.translation.height), geo.size)
                }
                .onEnded { _ in panStart = pan })
        }
        .focusable()
        .digitalCrownRotation($zoom, from: 1, through: 4, by: 0.1, sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: true)
        .onChange(of: zoom) { _, z in
            if z <= 1.01 { pan = .zero; panStart = .zero }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                // the sheet's own close button sits top left (a second one of ours doubled it)
                Color.clear.frame(height: 30)
                if let c = pic?.caption, !c.isEmpty {
                    caption(c)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.black.opacity(0.78)))
                        .accessibilityIdentifier("watchPictureCaption")
                }
            }
            .padding(.top, 6)
        }
        .overlay(alignment: .trailing) {
            if zoom > 1.05 {
                HStack(spacing: 3) {
                    Image(systemName: "plus.magnifyingglass")
                    Text(String(format: "%.0f×", zoom.rounded()))
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.78)))
                .padding(.trailing, 8)
                .accessibilityIdentifier("watchPictureZoom")
            }
        }
        .overlay(alignment: .bottom) {
            if pictures.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(pictures.enumerated()), id: \.offset) { i, p in
                        Button {
                            index = i
                        } label: {
                            Text(Self.short(p.caption, fallback: i == 0 ? "Before" : "After"))
                                .font(.system(size: 15, weight: i == index ? .semibold : .medium))
                                .foregroundStyle(i == index ? .white : Color(hex: 0xC8C8CC))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Capsule().fill(i == index ? Look.edge : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Color(hex: 0x141416).opacity(0.92)))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .accessibilityIdentifier("watchBeforeAfter")
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !started else { return }
            started = true
            index = open.index
            if store.demo, store.screen == "picture-full" { zoom = 2 }
        }
    }

    /// keeps the zoomed picture over the screen while dragging
    private func clamp(_ s: CGSize, _ size: CGSize) -> CGSize {
        let mx = size.width * (zoom - 1) / 2, my = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(s.width, -mx), mx), height: min(max(s.height, -my), my))
    }

    /// "After · The new grid": the first word bold
    private func caption(_ c: String) -> Text {
        let parts = c.components(separatedBy: " · ")
        guard parts.count > 1 else { return Text(c).font(.system(size: 13, weight: .medium)) }
        return Text(parts[0]).font(.system(size: 13, weight: .bold))
            + Text(" · " + parts.dropFirst().joined(separator: " · ")).font(.system(size: 13, weight: .medium))
    }

    /// "Before" from "Before · One per row"
    static func short(_ caption: String?, fallback: String = "Picture") -> String {
        let first = (caption ?? "").components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? fallback : first
    }
}
