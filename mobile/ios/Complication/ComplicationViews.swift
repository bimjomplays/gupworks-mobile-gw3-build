import SwiftUI
import WidgetKit

/// The watch face's complication (a235, docs/watch-mockups/round1 shared-1-complication). Drawn here so the widget
/// extension and the app's own demo (CI's screenshot, `-screen complication`) share one picture; the extension adds
/// the background and the tap (Complication.swift). The words and counts are GupKit's WatchComplication.

/// Circular: the count in a ring, violet for a question, amber for a permission, red while memory waits; a quiet check
/// when nothing waits, a dash before the iPhone has sent a list.
struct FaceCircular: View {
    let face: WatchComplication

    var body: some View {
        let colour = Look.tone(face.tone)
        ZStack {
            Circle().fill(colour.opacity(0.14))
            Circle().stroke(colour.opacity(0.3), lineWidth: 4.5)
            if face.count > 0 {
                Circle()
                    .trim(from: 0, to: face.ring)
                    .stroke(colour, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            if !face.known {
                Image(systemName: "minus").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
            } else if face.count == 0 {
                Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                Text("\(face.count)")
                    .font(.system(size: face.count > 9 ? 17 : 21, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
            }
        }
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.known ? (face.count == 0 ? "Nothing needs you" : "\(face.count) need you")
                                       : "Open GupWorks")
    }
}

/// Rectangular (and the Smart Stack's widget): "5 NEED YOU · 12m", the oldest one's project, its question.
struct FaceRectangular: View {
    let face: WatchComplication

    var body: some View {
        let colour = Look.tone(face.tone)
        VStack(alignment: .leading, spacing: 1) {
            if face.known, face.count > 0 {
                HStack(spacing: 5) {
                    ToneMark(tone: face.tone, size: 14)
                        .widgetAccentable()
                    Text(face.headline).foregroundStyle(colour.opacity(0.9)).lineLimit(1)
                    Spacer(minLength: 2)
                    if let wait = face.wait {
                        Text(wait).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                Text(face.source ?? "").font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(face.title ?? "").font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: face.known ? "checkmark.circle" : "iphone").widgetAccentable()
                    Text(face.headline).lineLimit(1)
                }
                .font(.system(size: 15, weight: .semibold))
                Text(face.known ? "Questions from your PC show up here." : "Your iPhone brings the cards to this watch.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
