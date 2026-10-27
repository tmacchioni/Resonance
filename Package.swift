// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "Resonance", defaultLocalization: "en", platforms: [.macOS(.v13)], products: [
    .executable(name: "Resonance", targets: ["Resonance"])
], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
   targets: [.executableTarget(name: "Resonance", dependencies: [.product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")])])
