// swift-tools-version: 6.0
// GupKit: the iPhone app's plain logic (models, API client, routes, pairing, stores, formats), with no SwiftUI or
// UIKit, so it builds and tests on Linux in seconds (`swift test` here). The app target compiles these same files
// into the app (mobile/ios/project.yml), so nothing needs to be `public`. See docs/mobile-fast-builds.md.
import PackageDescription

let package = Package(
    name: "GupKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "GupKit", targets: ["GupKit"])],
    targets: [
        .target(name: "GupKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "GupKitTests", dependencies: ["GupKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
