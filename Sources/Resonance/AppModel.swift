import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    let updates = AppUpdater()
    @Published var service: Service = .youtube
    @Published var link = ""
    @Published var options: ExportOptions
    @Published var collection: MediaCollection?
    @Published var jobs: [DownloadJob] = []
    @Published var inspecting = false
    @Published var error: String?
    @Published var tab = "download"
    @Published var showAbout = false
    @Published var log = ""
    @Published var showLog = false
    private var inspectTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    let engine: Engine

    var selectedCount: Int { collection?.items.filter(\.selected).count ?? 0 }
    var runningCount: Int { jobs.filter { !$0.state.terminal }.count }
    var completedCount: Int { jobs.filter { $0.state == .completed }.count }
    var busy: Bool { queueTask != nil }
    private var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Resonance/history.json")
    }

    init(engine: Engine = Engine()) {
        self.engine = engine
        let destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Resonance Media")
        if let data = UserDefaults.standard.data(forKey: "exportOptions"), let saved = try? JSONDecoder().decode(ExportOptions.self, from: data) {
            options = saved
        } else { options = ExportOptions(destination: destination) }
        if let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([DownloadJob].self, from: data) {
            jobs = saved.map { job in
                var restored = job
                if !restored.state.terminal { restored.state = .cancelled; restored.detail = "Interrotto alla chiusura. Puoi riprovare." }
                return restored
            }
        }
    }

    func selectService(_ value: Service) {
        guard value != service else { return }
        inspectTask?.cancel(); inspectTask = nil; inspecting = false
        service = value; collection = nil; error = nil; link = ""
        if value == .spotify { options.kind = .audio; options.format = .mp3 }
    }

    func setKind(_ value: MediaKind) {
        options.kind = value
        options.format = value == .audio ? .mp3 : .mp4
    }

    func paste() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        if let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["open.spotify.com", "spotify.link", "spoti.fi"].contains(url.host ?? "") || value.hasPrefix("spotify:") {
            selectService(.spotify)
        } else if (try? LinkValidator.normalized(value, for: .youtube)) != nil { selectService(.youtube) }
        link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        analyze()
    }

    func analyze() {
        inspectTask?.cancel()
        error = nil; collection = nil
        do {
            let url = try LinkValidator.normalized(link, for: service)
            let currentService = service
            inspecting = true
            inspectTask = Task {
                do {
                    let result = try await engine.inspect(url, service: currentService)
                    try Task.checkCancellation()
                    collection = result; inspecting = false
                } catch {
                    if !Task.isCancelled { self.error = Self.friendlyError(error); inspecting = false }
                }
            }
        } catch { self.error = error.localizedDescription; inspecting = false }
    }

    func cancelInspection() { inspectTask?.cancel(); inspecting = false }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = L("Scegli cartella"); panel.directoryURL = options.destination
        if panel.runModal() == .OK, let url = panel.url { options.destination = url; persist() }
    }

    func enqueue() {
        guard let collection else { return }
        var snapshot = options
        if service == .spotify { snapshot.kind = .audio }
        for item in collection.items where item.selected {
            guard !jobs.contains(where: { $0.item.id == item.id && !$0.state.terminal }) else { continue }
            jobs.append(DownloadJob(item: item, options: snapshot))
        }
        persist(); tab = "queue"; startQueue()
    }

    func startQueue() {
        guard queueTask == nil else { return }
        queueTask = Task {
            while !Task.isCancelled, let id = jobs.first(where: { $0.state == .waiting })?.id {
                let task = Task { await self.execute(id) }
                activeTask = task
                await task.value
                activeTask = nil
            }
            queueTask = nil; persist()
        }
    }

    private func execute(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do {
            var source = job.item.url
            if job.item.spotify {
                update(id) { $0.state = .matching; $0.detail = "Cerco una versione corrispondente su YouTube" }
                let match = try await engine.match(job.item)
                try Task.checkCancellation()
                source = match.url
                update(id) { $0.item.matchedURL = match.url; $0.item.matchedTitle = match.title }
            }
            update(id) { $0.state = .downloading; $0.detail = "Connessione alla sorgente…" }
            let file = try await engine.download(job.item, source: source, options: job.options) { [weak self] line in
                Task { @MainActor [weak self] in self?.receive(line, id: id) }
            }
            try Task.checkCancellation()
            update(id) { $0.state = .completed; $0.progress = 1; $0.detail = "Salvato"; $0.output = file.path }
        } catch {
            if Task.isCancelled { update(id) { $0.state = .cancelled; $0.detail = "Download annullato" } }
            else { update(id) { $0.state = .failed; $0.detail = Self.friendlyError(error) } }
        }
        persist()
    }

    private func receive(_ line: String, id: UUID) {
        log += line + "\n"
        if log.count > 60_000 { log = String(log.suffix(50_000)) }
        guard let job = jobs.first(where: { $0.id == id }), !job.state.terminal else { return }
        if let range = line.range(of: "RS_PROGRESS:") {
            let fields = line[range.upperBound...].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let value = fields.first?.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces) ?? "0"
            update(id) {
                $0.progress = min((Double(value) ?? 0) / 100, 1)
                $0.detail = fields.count >= 3 ? L("%@ · %@ · %@ rimanenti", fields[0].trimmingCharacters(in: .whitespaces), fields[1], fields[2]) : L("Download in corso")
            }
        } else if line.hasPrefix("[ExtractAudio]") || line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") || line.hasPrefix("RS_PROCESS:") {
            update(id) { $0.state = .processing; $0.detail = "Preparazione del file finale…" }
        }
    }

    private func update(_ id: UUID, _ action: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        action(&jobs[index])
    }

    func cancel(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), !job.state.terminal else { return }
        if job.state != .waiting { activeTask?.cancel() }
        update(id) { $0.state = .cancelled; $0.detail = "Annullato" }
        persist()
    }

    func cancelAll() {
        queueTask?.cancel(); activeTask?.cancel()
        for index in jobs.indices where !jobs[index].state.terminal { jobs[index].state = .cancelled; jobs[index].detail = "Annullato" }
        persist()
    }

    func retry(_ id: UUID) {
        guard let previous = jobs.first(where: { $0.id == id }), previous.state.terminal else { return }
        jobs.append(DownloadJob(item: previous.item, options: previous.options))
        persist(); startQueue()
    }

    func reveal(_ job: DownloadJob) {
        if let path = job.output { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "exportOptions") }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let active = jobs.filter { !$0.state.terminal }
            let history = Array(jobs.filter { $0.state.terminal }.suffix(200))
            try JSONEncoder().encode(active + history).write(to: historyURL, options: .atomic)
        } catch { log += "Cronologia non salvata: \(error.localizedDescription)\n" }
    }

    static func friendlyError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("sign in") || lower.contains("bot") { return L("YouTube richiede una verifica di accesso per questo contenuto o questa rete. Riprova più tardi o usa un altro video pubblico.") }
        if lower.contains("requested format") { return L("Il formato o la risoluzione richiesti non sono disponibili. Prova MKV, una qualità inferiore o solo audio.") }
        if lower.contains("private") || lower.contains("unavailable") { return L("Questo contenuto è privato, rimosso o non disponibile nella tua regione.") }
        return message
    }
}
