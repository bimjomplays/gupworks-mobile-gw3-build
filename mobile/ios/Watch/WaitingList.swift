import SwiftUI

/// "Needs you" (round 1 shared screen 2): everything that waits, the memory warning on top, then oldest first with its
/// wait; the current card marked blue, a tap opens that card. Parked projects at the bottom with Bring back.
struct WaitingList: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let deck = store.deck
        let current = store.current?.key
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(deck.cards) { c in
                    Button {
                        store.select(c.key)
                        dismiss()
                    } label: {
                        if c.kind == .memory {
                            memoryRow(c)
                        } else {
                            row(c, current: c.key == current)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchListRow")
                }
                if !deck.parked.isEmpty {
                    Text("Parked · \(deck.parked.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x8E8E93))
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                    ForEach(deck.parked, id: \.projectId) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.name).font(.system(size: 16, weight: .medium))
                                Spacer()
                                Text(p.items == 1 ? "1 waits" : "\(p.items) wait")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Look.dim)
                            }
                            Button { store.bringBack(p) } label: { PillLabel(title: "Bring back", fill: Look.mic) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("watchBringBack")
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Look.row))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Needs you")
    }

    private func memoryRow(_ c: WatchCard) -> some View {
        HStack(spacing: 8) {
            ToneMark(tone: .red, size: 22)
            Text(c.listTitle).font(.system(size: 16, weight: .medium)).foregroundStyle(Look.memoryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color(hex: 0x3A1C1E)))
        .overlay(Capsule().stroke(Color(hex: 0x6A2A2C), lineWidth: 1))
    }

    private func row(_ c: WatchCard, current: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ToneMark(tone: c.tone, size: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(c.source) · \(WatchCard.wait(store.pcNow - c.since))")
                    .font(.system(size: 13))
                    .foregroundStyle(Look.source)
                    .lineLimit(1)
                Text(c.listTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Look.row))
        .overlay(alignment: .leading) {
            if current {
                UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                    .fill(Color(hex: 0x6EA8FF))
                    .frame(width: 3)
            }
        }
        .accessibilityValue(current ? "current" : "")
    }
}
