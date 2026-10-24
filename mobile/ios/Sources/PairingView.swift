import SwiftUI

/// First start: pair with the PC. On the PC, `gw3-phone pair` shows a QR code; scan it here (or with the iPhone
/// camera, which opens the app through its gupworks3:// link), or paste the link it prints.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: QRScanner.StartResult?
    @State private var pasted = ""
    @State private var problem: String?
    @State private var busy = false
    @State private var lastTried = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pair with your PC")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.title)
                    Text("On the PC, run gw3-phone pair and scan the code it shows. Your phone and PC both need Tailscale on.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }

                cameraBox

                VStack(alignment: .leading, spacing: 10) {
                    Text("Or paste the pairing link")
                        .font(.subheadline)
                        .foregroundStyle(Theme.section)
                    HStack(spacing: 10) {
                        TextField("gupworks3://pair?…", text: $pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit { tryCode(pasted) }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .glassEffect(in: .capsule)
                            .accessibilityIdentifier("pairCode")
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in
                                pasted = text
                                tryCode(text)
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                    }
                    Button {
                        tryCode(pasted)
                    } label: {
                        Text("Pair").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }

                if busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Pairing…").foregroundStyle(Theme.secondary)
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                        .accessibilityIdentifier("pairProblem")
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .onChange(of: model.incomingLink) { _, link in
            guard let link else { return }
            model.incomingLink = nil
            pasted = link
            tryCode(link)
        }
    }

    @ViewBuilder
    private var cameraBox: some View {
        ZStack {
            if !model.demo {
                QRCameraView(onCode: { text in
                    // the camera repeats a code while it stays in view: try each text once
                    if text != lastTried { tryCode(text) }
                }, onState: { camera = $0 })
            }
            switch camera {
            case .denied:
                cameraNote("The camera is off for GupWorks. Allow it in Settings, or paste the link below.",
                           icon: "video.slash")
            case .noCamera, .none where model.demo:
                cameraNote("No camera here. Paste the link below.", icon: "camera")
            case .none:
                ProgressView()
            case .running:
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 200, height: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private func cameraNote(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle)
            Text(text).font(.subheadline).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.secondary)
        .padding(24)
    }

    private func tryCode(_ text: String) {
        guard !busy else { return }
        lastTried = text
        switch PairLink.parse(text) {
        case .failure(let p):
            problem = p.message
        case .success(let link):
            problem = nil
            busy = true
            Task {
                do {
                    try await model.pair(with: link)
                } catch let e as APIError {
                    problem = e.message
                } catch {
                    problem = APIError.from(error).message
                }
                busy = false
            }
        }
    }
}
