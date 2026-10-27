import SwiftUI

/// a142: Quick actions. Away mode and Dillon's game bot are switches that only move when the PC says they did; Restart
/// PC is a button that asks "Restart the PC now?" first. Every state is read again after each action and whenever the
/// page or the app comes back; errors show in red under their switch. a151 adds the PC's health line on top and Media,
/// Volume, Open on the PC and Discord call under the switches (QuickPcSections.swift).
struct QuickActionsView: View {
    @Environment(\.scenePhase) private var phase
    @State private var store: QuickStore
    @State private var pc: QuickPcStore
    /// the dialog's one-time token from the PC (gw3-phone /v1/quick/restart-pc/confirm): the dialog shows while set
    @State private var confirm: QuickConfirm?
    @State private var asking = false

    init(pairing: Pairing?, demo: Bool) {
        _store = State(initialValue: QuickStore(pairing: pairing, demo: demo))
        _pc = State(initialValue: QuickPcStore(pairing: pairing, demo: demo))
        if demo && Demo.args.contains("-restartAsk") {
            _confirm = State(initialValue: QuickConfirm(confirm: "demo", question: "Restart the PC now?", seconds: 60))
        }
    }

    var body: some View {
        List {
            if let e = store.error {
                Section {
                    Text(e.message).font(.system(size: 14)).foregroundStyle(Theme.red)
                        .accessibilityIdentifier("quickError")
                }
            }
            QuickHealthSection(store: pc)
            Section {
                ForEach(store.switches) { s in
                    if s.isToggle { toggleRow(s) } else { restartRow(s) }
                }
                if store.switches.isEmpty && store.error == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Theme.background)
                }
            } footer: {
                Text("Read from the PC each time you come back to this page.")
            }
            QuickPcSections(store: pc)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Quick actions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await readAll() }
        .task {
            store.forgetTries()
            pc.forgetTries()
            await readAll()
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await readAll() } }
        }
        .alert(confirm?.question ?? "Restart the PC now?",
               isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { c in
            Button("Cancel", role: .cancel) { confirm = nil }
            Button("Restart", role: .destructive) {
                confirm = nil
                Task { await store.restart(c) }
            }
            .accessibilityIdentifier("restartConfirm")
        } message: { _ in
            Text("Everything open on the PC closes and it starts again.")
        }
    }

    /// the switches and the PC part, side by side
    private func readAll() async {
        async let switches: Void = store.refresh()
        async let rest: Void = pc.refresh()
        _ = await (switches, rest)
    }

    private func toggleRow(_ s: QuickSwitch) -> some View {
        let busy = store.busy.contains(s.id)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { s.on ?? false }, set: { on in Task { await store.set(s.id, on: on) } })) {
                HStack(spacing: 8) {
                    Text(s.label).foregroundStyle(Theme.rowTitle)
                    if busy { ProgressView().controlSize(.small) }
                }
            }
            .tint(Theme.blue)
            .disabled(busy)
            .accessibilityIdentifier("quick-\(s.id)")
            notes(s, detail: busy ? "Switching…" : s.on == nil ? "State unknown" : nil)
        }
    }

    private func restartRow(_ s: QuickSwitch) -> some View {
        let busy = store.busy.contains(s.id) || asking
        let allowed = s.allowed == true && !store.restarting
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.label).foregroundStyle(Theme.rowTitle)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Restart") {
                    Task {
                        asking = true
                        confirm = await store.askRestart()
                        asking = false
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.red)
                .disabled(!allowed || busy)
                .accessibilityIdentifier("quickRestart")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quick-\(s.id)")
            notes(s, detail: store.restarting ? "Restarting…"
                : s.allowed == true ? "Restarts this PC after you confirm"
                : (s.reason?.isEmpty == false ? s.reason : "Can't restart now"))
        }
    }

    @ViewBuilder
    private func notes(_ s: QuickSwitch, detail: String?) -> some View {
        if let d = detail ?? (s.detail?.isEmpty == false ? s.detail : nil) {
            Text(d).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("quick-\(s.id)-detail")
        }
        if let w = s.warning, !w.isEmpty {
            Label(w, systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Theme.amber)
                .accessibilityIdentifier("quick-\(s.id)-warning")
        }
        if let e = store.errorText(s.id) {
            Text(e).font(.system(size: 13)).foregroundStyle(Theme.red)
                .accessibilityIdentifier("quick-\(s.id)-error")
        }
    }
}
