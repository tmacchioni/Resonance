import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published var automaticallyChecks = true
    @Published private(set) var configured = false
    private var controller: SPUStandardUpdaterController?
    private weak var model: AppModel?
    private var postponedInstall: AnyCancellable?
    private var started = false

    func start(model: AppModel) {
        guard !started else { return }
        started = true
        self.model = model
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        configured = true
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates { controller.updater.checkForUpdatesInBackground() }
    }

    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard model?.busy != true else {
            throw NSError(domain: "it.resonance.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Attendi il completamento dei download prima di verificare gli aggiornamenti.")])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let model, model.runningCount > 0 else { model?.persist(); return false }
        postponedInstall = model.$jobs
            .filter { $0.allSatisfy { $0.state.terminal } }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.model?.persist()
                installHandler()
                self?.postponedInstall = nil
            }
        return true
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button("Verifica aggiornamenti…") { updater.check() }.disabled(!updater.canCheck)
    }
}

struct UpdatePreferencesView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Controlla automaticamente gli aggiornamenti", isOn: Binding(
                get: { updater.automaticallyChecks }, set: { updater.setAutomaticChecks($0) }))
                .disabled(!updater.configured)
            Text("Una nuova versione richiede sempre la tua conferma prima dell’installazione.")
                .font(.caption).foregroundStyle(.secondary)
            CheckForUpdatesView(updater: updater)
        }
    }
}
