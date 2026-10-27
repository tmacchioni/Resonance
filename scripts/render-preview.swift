import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() {
        if CommandLine.arguments.count > 2 {
            UserDefaults.standard.setVolatileDomain([AppLanguage.preferenceKey: CommandLine.arguments[2]], forName: UserDefaults.argumentDomain)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel()
        let frame = NSRect(x: 0, y: 0, width: 1160, height: 920)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: ContentView(model: model))
        hosting.frame = frame
        window.contentView = hosting
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            do {
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                app.terminate(nil)
            } catch { print(error); exit(1) }
        }
        app.run()
    }
}
