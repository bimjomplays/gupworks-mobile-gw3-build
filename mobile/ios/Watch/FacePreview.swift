import SwiftUI

/// The demo's stand-in for a watch face with the complications on it (CI's screenshot, `-screen complication`; the
/// simulator can't put a complication on a face by script): round 1's shared screen 1, with the extension's own two
/// pictures (Complication/ComplicationViews.swift) on a face with the time, a date and two other circles.
/// `-screen complication-empty` shows the quiet state.
struct FacePreview: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        var list = store.list
        if store.screen == "complication-empty" { list?.needs.items = [] }
        let face = WatchComplication(list, now: store.now)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("FRI 20").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xFF9F6E))
                Spacer()
                Text("10:09").font(.system(size: 42, weight: .medium)).tracking(-1.5)
            }
            .padding(.horizontal, 14)
            FaceRectangular(face: face)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x141218)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x2A2538), lineWidth: 1))
                .padding(.horizontal, 10)
                .padding(.top, 6)
            Spacer(minLength: 6)
            HStack {
                FaceCircular(face: face).frame(width: 50, height: 50)
                Spacer()
                other("12°")
                Spacer()
                other("72")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .padding(.top, 4)
        .background(Color.black)
    }

    private func other(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x9A9AA0))
            .frame(width: 50, height: 50)
            .background(Circle().fill(Color(hex: 0x18181A)))
    }
}
