// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Read the same catalog used by the standalone build and release scripts.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("vendor/manifest.json"))) as! [String: Any]
let versions = catalog["versions"] as! [String: String]
let sparkleVersion = Version(versions["sparkle"]!)!

let package = Package(
    name: "Resonance",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Resonance", targets: ["Resonance"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: sparkleVersion)
    ],
    targets: [
        .executableTarget(
            name: "Resonance",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")]
        )
    ]
)
