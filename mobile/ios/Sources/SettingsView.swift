import SwiftUI

/// Settings (was the third tab; rarely used, so it sits behind the gear): This PC and Unpair.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                if let p = model.pairing {
                    Section("This PC") {
                        LabeledContent("Name", value: model.hello?.pc ?? p.pcName)
                        LabeledContent("Address", value: p.baseURL.host ?? "")
                        LabeledContent("Paired", value: p.pairedAt.formatted(date: .abbreviated, time: .shortened))
                        if let v = model.hello?.version {
                            LabeledContent("GupWorks phone service", value: v)
                        }
                        if let t = model.lastRefresh {
                            LabeledContent("Last update", value: t.formatted(date: .omitted, time: .standard))
                        }
                    }
                    Section {
                        Button("Unpair this phone", role: .destructive) { confirmUnpair = true }
                            .accessibilityIdentifier("unpair")
                    } footer: {
                        Text("Forgets the PC's key on this phone. To also make the PC forget every phone, run gw3-phone revoke on the PC.")
                    }
                }
                Section("App") {
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Unpair this phone?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) {
                    dismiss()
                    model.unpair()
                }
            } message: {
                Text("You'll need a new code from the PC to pair again.")
            }
        }
        .presentationBackground(Theme.background)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
