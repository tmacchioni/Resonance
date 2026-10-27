import Foundation

enum Service: String, CaseIterable, Codable {
    case spotify = "Spotify", youtube = "YouTube"
    var symbol: String { self == .spotify ? "waveform" : "play.rectangle.fill" }
}

enum MediaKind: String, CaseIterable, Codable { case audio = "Audio", video = "Video" }
enum OutputFormat: String, CaseIterable, Codable {
    case mp3 = "MP3", m4a = "M4A", flac = "FLAC", wav = "WAV", opus = "OPUS"
    case mp4 = "MP4", mkv = "MKV", webm = "WebM"
    static let audio: [Self] = [.mp3, .m4a, .flac, .wav, .opus]
    static let video: [Self] = [.mp4, .mkv, .webm]
    var lossless: Bool { self == .flac || self == .wav }
    var extensionName: String { rawValue.lowercased() }
}

struct ExportOptions: Codable {
    var kind: MediaKind = .audio
    var format: OutputFormat = .mp3
    var bitrate = "320"
    var height = "1080"
    var destination: URL
}

struct MediaItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var artist: String
    var duration: Double?
    var url: String
    var artwork: String?
    var spotify: Bool = false
    var selected: Bool = true
    var album: String?
    var position: Int?
    var matchedURL: String?
    var matchedTitle: String?
    var durationText: String {
        guard let duration, duration > 0 else { return "—" }
        let seconds = Int(duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct MediaCollection {
    var title: String
    var items: [MediaItem]
    var notice: String?
}

enum JobState: String, Codable {
    case waiting = "In coda", matching = "Ricerca sorgente", downloading = "Download"
    case processing = "Conversione", completed = "Completato", failed = "Errore", cancelled = "Annullato"
    var terminal: Bool { [.completed, .failed, .cancelled].contains(self) }
}

struct DownloadJob: Identifiable, Codable {
    var id = UUID()
    var item: MediaItem
    var options: ExportOptions
    var state: JobState = .waiting
    var progress: Double = 0
    var detail = "In attesa"
    var output: String?
    var date = Date()
}

enum ResonanceError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

enum LinkValidator {
    static func normalized(_ input: String, for service: Service) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if service == .spotify, value.hasPrefix("spotify:") {
            let parts = value.split(separator: ":")
            guard parts.count == 3 else { throw ResonanceError.message(L("Il link Spotify non è valido.")) }
            value = "https://open.spotify.com/\(parts[1])/\(parts[2])"
        }
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil else {
            throw ResonanceError.message(L("Incolla un link HTTPS valido di %@.", service.rawValue))
        }
        switch service {
        case .spotify:
            guard ["open.spotify.com", "spotify.link", "spoti.fi"].contains(host) else {
                throw ResonanceError.message(L("Questo non è un link Spotify."))
            }
            if host == "open.spotify.com" {
                _ = try spotifyParts(url)
            }
        case .youtube:
            guard ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"].contains(host) else {
                throw ResonanceError.message(L("Questo non è un link YouTube."))
            }
            let path = url.pathComponents.filter { $0 != "/" }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let valid: Bool
            if host == "youtu.be" { valid = path.count == 1 && !path[0].isEmpty }
            else { valid = (url.path == "/watch" && query.contains { $0.name == "v" && !($0.value ?? "").isEmpty })
                || (url.path == "/playlist" && query.contains { $0.name == "list" && !($0.value ?? "").isEmpty })
                || (path.count == 2 && ["shorts", "live", "embed"].contains(path[0])) }
            guard valid else { throw ResonanceError.message(L("Usa il link di un video, Short o playlist, non quello di un canale.")) }
        }
        return url
    }

    static func spotifyParts(_ url: URL) throws -> (String, String) {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") && $0 != "embed" }
        guard parts.count == 2, ["track", "album", "playlist"].contains(parts[0]),
              parts[1].count == 22, parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw ResonanceError.message(L("Usa il link di un brano, album o playlist Spotify pubblica."))
        }
        return (parts[0], parts[1])
    }
}
