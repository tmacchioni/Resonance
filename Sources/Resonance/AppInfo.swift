import Foundation

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var repositoryURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ResonanceRepositoryURL") as? String else { return nil }
        return URL(string: value)
    }
}
