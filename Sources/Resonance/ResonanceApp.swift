import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true {
            let alert = NSAlert(); alert.messageText = L("Ci sono download in corso")
            alert.informativeText = L("Chiudendo Resonance i download in corso verranno annullati. Potrai riprovarli dalla cronologia.")
            alert.addButton(withTitle: L("Continua i download")); alert.addButton(withTitle: L("Annulla e chiudi"))
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            model?.cancelAll()
        }
        model?.persist()
        return .terminateNow
    }
}

@main
struct ResonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.selected
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environment(\.locale, Locale(identifier: language))
                .onAppear { delegate.model = model; model.updates.start(model: model) }
        }
        .defaultSize(width: 1160, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Nuovo download")) { model.tab = "download" }.keyboardShortcut("n")
                Button(L("Incolla e analizza link")) { model.paste() }.keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appInfo) { Button(L("Informazioni su Resonance")) { model.showAbout = true } }
            CommandGroup(after: .appInfo) { CheckForUpdatesView(updater: model.updates) }
        }
    }
}
