import Foundation
import Darwin

final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }

    func cancel() {
        lock.lock(); cancelled = true; let current = process; lock.unlock()
        guard let current, current.isRunning else { return }
        // Stop FFmpeg/JS children too; only descendants of this specific job are affected.
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid="]
        let pipe = Pipe(); ps.standardOutput = pipe; ps.standardError = FileHandle.nullDevice
        if (try? ps.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); ps.waitUntilExit()
            let pairs = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> (Int32, Int32)? in
                let values = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }
                return values.count == 2 ? (values[0], values[1]) : nil
            }
            var descendants: Set<Int32> = [current.processIdentifier]
            var changed = true
            while changed {
                changed = false
                for (pid, parent) in pairs where descendants.contains(parent) && !descendants.contains(pid) {
                    descendants.insert(pid); changed = true
                }
            }
            for pid in descendants where pid != current.processIdentifier { kill(pid, SIGTERM) }
        }
        if current.isRunning { current.terminate() }
    }
}

enum ProcessRunner {
    static func run(_ executable: URL, _ arguments: [String], line: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let running = RunningProcess()
        return try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                let process = Process(); process.executableURL = executable; process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = executable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
                env["LC_ALL"] = "en_US.UTF-8"
                process.environment = env
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                try running.launch(process)
                var pending = Data(); var output = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    output.append(chunk)
                    // Keep diagnostic output bounded during very long playlists.
                    if output.count > 8_000_000 { output.removeFirst(output.count - 8_000_000) }
                    pending.append(chunk)
                    while let index = pending.firstIndex(of: 10) {
                        let record = pending.prefix(upTo: index)
                        line(String(decoding: record, as: UTF8.self))
                        pending.removeSubrange(...index)
                    }
                }
                if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
                process.waitUntilExit()
                let text = String(decoding: output, as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    let errors = text.split(separator: "\n").filter { $0.contains("ERROR:") }
                    throw ResonanceError.message(String((errors.last.map(String.init) ?? String(text.suffix(1800)))))
                }
                return text
            }.value
        }, onCancel: { running.cancel() })
    }
}

struct Engine {
    let tools: URL

    init(tools: URL? = nil) {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        self.tools = tools ?? Bundle.main.resourceURL!.appendingPathComponent("Tools/\(arch)")
    }

    func checkTools() throws {
        for name in ["yt-dlp", "ffmpeg", "ffprobe", "qjs"] {
            guard FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent(name).path) else {
                throw ResonanceError.message(L("Il componente %@ manca o non è eseguibile. Reinstalla il pacchetto completo di Resonance.", name))
            }
        }
    }

    var baseArguments: [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-update", "--no-colors", "--socket-timeout", "25",
         "--retries", "3", "--extractor-retries", "2", "--ffmpeg-location", tools.path,
         "--no-js-runtimes", "--js-runtimes", "quickjs:\(tools.appendingPathComponent("qjs").path)"]
    }

    func yt(_ args: [String], line: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        try checkTools()
        return try await ProcessRunner.run(tools.appendingPathComponent("yt-dlp"), baseArguments + args, line: line)
    }

    func inspect(_ url: URL, service: Service) async throws -> MediaCollection {
        if service == .spotify { return try await SpotifyResolver.resolve(url) }
        let text = try await yt(["--flat-playlist", "--dump-single-json", "--skip-download", "--", url.absoluteString])
        let object = try Self.jsonObject(text)
        let entries = object["entries"] as? [[String: Any]] ?? [object]
        let items = entries.compactMap { Self.youtubeItem($0) }
        guard !items.isEmpty else { throw ResonanceError.message(L("Nessun contenuto pubblico disponibile a questo link.")) }
        return MediaCollection(title: object["title"] as? String ?? "YouTube", items: items)
    }

    static func jsonObject(_ output: String) throws -> [String: Any] {
        // yt-dlp may put warning lines before its single JSON document.
        for line in output.split(separator: "\n").reversed() where line.hasPrefix("{") {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] { return obj }
        }
        throw ResonanceError.message(L("Risposta della sorgente non valida. Riprova o aggiorna Resonance."))
    }

    static func youtubeItem(_ object: [String: Any]) -> MediaItem? {
        guard let id = object["id"] as? String, let title = object["title"] as? String,
              title != "[Deleted video]", title != "[Private video]" else { return nil }
        let url = object["webpage_url"] as? String ?? object["url"] as? String ?? "https://www.youtube.com/watch?v=\(id)"
        guard let valid = try? LinkValidator.normalized(url, for: .youtube) else { return nil }
        let thumbnails = object["thumbnails"] as? [[String: Any]]
        return MediaItem(id: id, title: title, artist: object["uploader"] as? String ?? object["channel"] as? String ?? "YouTube",
                         duration: object["duration"] as? Double, url: valid.absoluteString,
                         artwork: object["thumbnail"] as? String ?? thumbnails?.last?["url"] as? String)
    }

    func match(_ item: MediaItem) async throws -> MediaItem {
        if let custom = item.matchedURL, !custom.isEmpty {
            let url = try LinkValidator.normalized(custom, for: .youtube)
            let collection = try await inspect(url, service: .youtube)
            guard collection.items.count == 1, let result = collection.items.first else {
                throw ResonanceError.message(L("Per la sorgente di un brano scegli un singolo video YouTube."))
            }
            return result
        }
        let query = "ytsearch5:\(item.artist) \(item.title) official audio"
        let text = try await yt(["--flat-playlist", "--dump-single-json", "--skip-download", "--", query])
        let entries = try Self.jsonObject(text)["entries"] as? [[String: Any]] ?? []
        let candidates = entries.compactMap { Self.youtubeItem($0) }
        let ranked = candidates.map { candidate -> (MediaItem, Double) in
            let words = Set(item.title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
            let name = candidate.title.lowercased()
            let overlap = words.isEmpty ? 0 : Double(words.filter { name.contains($0) }.count) / Double(words.count)
            let durationScore: Double
            if let a = item.duration, let b = candidate.duration { durationScore = abs(a - b) <= max(12, a * 0.08) ? 0.35 : -0.6 }
            else { durationScore = 0 }
            let artist = item.artist.components(separatedBy: ",").first?.lowercased() ?? ""
            let artistScore = (name + " " + candidate.artist.lowercased()).contains(artist) ? 0.2 : 0
            return (candidate, overlap * 0.6 + durationScore + artistScore)
        }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 0.7 else {
            throw ResonanceError.message(L("Non ho trovato una corrispondenza affidabile. Imposta il link YouTube del brano dall’anteprima e riprova."))
        }
        return best.0
    }

    static func downloadArguments(item: MediaItem, source: String, options: ExportOptions, directory: URL) -> [String] {
        var args = ["--no-playlist", "--newline", "--progress", "--progress-delta", "0.3",
                    "--progress-template", "download:RS_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                    "--print", "after_move:RS_FILE:%(filepath)s", "--no-simulate", "--no-overwrites",
                    "--windows-filenames", "--trim-filenames", "180", "--paths", directory.path,
                    "--output", "%(title).150B [%(id)s].%(ext)s", "--embed-metadata"]
        if options.kind == .audio {
            args += ["--format", "bestaudio/best", "--extract-audio", "--audio-format", options.format.extensionName]
            if !options.format.lossless {
                // libopus rejects >256 kbps for mono sources. Keep the menu and engine safe for either channel layout.
                let bitrate = options.format == .opus ? String(min(Int(options.bitrate) ?? 256, 256)) : options.bitrate
                args += ["--audio-quality", "\(bitrate)K"]
            }
        } else {
            let cap = options.height == "best" ? "" : "[height<=\(options.height)]"
            switch options.format {
            case .mp4:
                // Constrain codecs as well as container, to produce broadly playable MP4.
                args += ["--format", "bv*\(cap)[vcodec^=avc1]+ba[ext=m4a]/b\(cap)[ext=mp4][vcodec^=avc1]",
                         "--merge-output-format", "mp4", "--remux-video", "mp4"]
            case .webm:
                args += ["--format", "bv*\(cap)[ext=webm]+ba[ext=webm]/b\(cap)[ext=webm]",
                         "--merge-output-format", "webm", "--remux-video", "webm"]
            default:
                args += ["--format", "bv*\(cap)+ba/b\(cap)", "--merge-output-format", "mkv", "--remux-video", "mkv"]
            }
        }
        args += ["--", source]
        return args
    }

    func download(_ item: MediaItem, source: String, options: ExportOptions,
                  line: @escaping @Sendable (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: options.destination, withIntermediateDirectories: true)
        let staging = options.destination.appendingPathComponent(".resonance-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let result = try await yt(Self.downloadArguments(item: item, source: source, options: options, directory: staging), line: line)
        try Task.checkCancellation()
        guard let file = result.split(separator: "\n").last(where: { $0.hasPrefix("RS_FILE:") }) else {
            throw ResonanceError.message(L("Il motore non ha restituito il file finale."))
        }
        let downloaded = URL(fileURLWithPath: String(file.dropFirst("RS_FILE:".count)))
        guard downloaded.standardizedFileURL.deletingLastPathComponent() == staging.standardizedFileURL,
              fm.fileExists(atPath: downloaded.path) else {
            throw ResonanceError.message(L("Il file convertito non è disponibile."))
        }
        let final: URL
        if item.spotify {
            line("RS_PROCESS:Scrittura dei metadati Spotify")
            let tagged = staging.appendingPathComponent("tagged.\(options.format.extensionName)")
            var args = ["-nostdin", "-v", "error", "-i", downloaded.path, "-map", "0", "-c", "copy",
                        "-metadata", "title=\(item.title)", "-metadata", "artist=\(item.artist)"]
            if let album = item.album { args += ["-metadata", "album=\(album)"] }
            if let position = item.position { args += ["-metadata", "track=\(position)"] }
            args += [tagged.path]
            _ = try await ProcessRunner.run(tools.appendingPathComponent("ffmpeg"), args)
            final = tagged
        } else { final = downloaded }
        try Task.checkCancellation()
        let stem = item.spotify ? "\(item.position.map { String(format: "%03d - ", $0) } ?? "")\(item.artist) - \(item.title)" : downloaded.deletingPathExtension().lastPathComponent
        let safe = Self.safeFilename(stem)
        var target = options.destination.appendingPathComponent(safe).appendingPathExtension(options.format.extensionName)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = options.destination.appendingPathComponent("\(safe) (\(suffix))").appendingPathExtension(options.format.extensionName)
            suffix += 1
        }
        try fm.moveItem(at: final, to: target)
        return target
    }

    static func safeFilename(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let clean = text.components(separatedBy: forbidden).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? L("Audio") : String(clean.prefix(150))
    }
}

enum SpotifyResolver {
    static func resolve(_ link: URL) async throws -> MediaCollection {
        var resolved = link
        if link.host != "open.spotify.com" {
            let (_, response) = try await URLSession.shared.data(from: link)
            guard let url = response.url, url.host == "open.spotify.com" else {
                throw ResonanceError.message(L("Il link breve Spotify non è disponibile."))
            }
            resolved = url
        }
        let (kind, id) = try LinkValidator.spotifyParts(resolved)
        let url = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)")!
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ResonanceError.message(L("Spotify non rende disponibile questo contenuto. Verifica che il link sia pubblico."))
        }
        return try parse(String(decoding: data, as: UTF8.self), kind: kind)
    }

    static func parse(_ html: String, kind: String) throws -> MediaCollection {
        let regex = try NSRegularExpression(pattern: "<script[^>]*id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>", options: .dotMatchesLineSeparators)
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range), let dataRange = Range(match.range(at: 1), in: html),
              let root = try JSONSerialization.jsonObject(with: Data(html[dataRange].utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let data = state["data"] as? [String: Any],
              let entity = data["entity"] as? [String: Any] else {
            throw ResonanceError.message(L("Spotify non espone l’elenco pubblico per questo link. Il contenuto può essere privato o la pagina è cambiata."))
        }
        let title = entity["title"] as? String ?? entity["name"] as? String ?? "Spotify"
        let visual = entity["visualIdentity"] as? [String: Any]
        let artwork = (visual?["image"] as? [[String: Any]])?.last?["url"] as? String
        let rows: [[String: Any]] = kind == "track" ? [entity] : entity["trackList"] as? [[String: Any]] ?? []
        let items = rows.enumerated().compactMap { offset, row -> MediaItem? in
            guard let uri = row["uri"] as? String, uri.hasPrefix("spotify:track:"), let name = row["title"] as? String ?? row["name"] as? String else { return nil }
            let artists = (row["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
            let artist = row["subtitle"] as? String ?? artists ?? entity["subtitle"] as? String ?? ""
            return MediaItem(id: uri, title: name, artist: artist.replacingOccurrences(of: "\u{00a0}", with: " "),
                             duration: (row["duration"] as? Double).map { $0 / 1000 },
                             url: "https://open.spotify.com/track/\(uri.components(separatedBy: ":").last!)", artwork: artwork,
                             spotify: true, album: kind == "album" ? title : nil, position: kind == "track" ? nil : offset + 1)
        }
        guard !items.isEmpty else { throw ResonanceError.message(L("Nessun brano pubblico trovato. Le playlist private e i file locali non sono disponibili.")) }
        return MediaCollection(title: title, items: items, notice: kind == "track" ? nil :
            L("Spotify espone %ld brani nell’anteprima pubblica. L’elenco può essere parziale: confrontalo con la raccolta originale prima di scaricare.", items.count))
    }
}
