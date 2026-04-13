import Foundation
import SwiftUI

/// Global app configuration backed by `@AppStorage` / `UserDefaults`.
/// Injected into the environment so SwiftUI views can bind directly.
///
/// Not marked `@MainActor` on purpose: the `MLXClient` baseURL closure runs on
/// whatever Task context drives `URLSession`, and it needs to read the
/// current server URL without hopping actors. We satisfy that by reading
/// `UserDefaults` directly in `makeBaseURL()`, which is thread-safe.
final class AppSettings: ObservableObject {

    @AppStorage("settings.baseURL")
    var baseURLString: String = "http://localhost:8080"

    @AppStorage("settings.defaultTemperature")
    var defaultTemperature: Double = 0.7

    @AppStorage("settings.defaultTopP")
    var defaultTopP: Double = 1.0

    @AppStorage("settings.defaultMaxTokens")
    var defaultMaxTokens: Int = 1024

    @AppStorage("settings.defaultSystemPrompt")
    var defaultSystemPrompt: String = ""

    @AppStorage("settings.defaultModelId")
    var defaultModelId: String = ""

    // MARK: - Keys (must match the @AppStorage names above)

    private enum Keys {
        static let baseURL = "settings.baseURL"
    }

    /// Main-actor-safe accessor for the current URL, used from SwiftUI views.
    var baseURL: URL { Self.makeBaseURL() }

    /// Thread-safe URL snapshot for networking. Reads straight from
    /// `UserDefaults` so it can be called from any Task.
    static func makeBaseURL() -> URL {
        let str = UserDefaults.standard.string(forKey: Keys.baseURL)
            ?? "http://localhost:8080"
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }
}
