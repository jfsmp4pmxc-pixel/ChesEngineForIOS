import Foundation
import SwiftUI

// MARK: - Locations

enum Paths {
    static var documents: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var games: URL { folder("Games") }
    static var bots: URL { folder("Bots") }

    private static func folder(_ name: String) -> URL {
        let url = documents.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Preferences

enum Prefs {
    static let profileKey = "engineProfile"
    /// Whether pieces slide from one square to the other (on by default).
    static let animateKey = "animateMoves"
    /// How long a piece takes to glide to its square, in seconds.
    static let slideDurationKey = "slideDuration"
    static let defaultSlideDuration = 0.25
    /// Rating used to tune move classification (lower ratings are judged more leniently).
    static let ratingKey = "playerRating"
    static let defaultRating = 1500
    /// Classify each move right after it is played (off by default: it uses the engine a lot).
    static let liveKey = "liveAnalysis"
    /// Also classify the opponent's moves during live analysis.
    static let liveOpponentKey = "liveAnalysisOpponent"

    static var liveAnalysis: Bool {
        return UserDefaults.standard.object(forKey: liveKey) as? Bool ?? false
    }

    static var rating: Int {
        let v = UserDefaults.standard.integer(forKey: ratingKey)
        return v == 0 ? defaultRating : max(400, min(3000, v))
    }

    static var profile: EngineProfile {
        get {
            let raw = UserDefaults.standard.string(forKey: profileKey) ?? EngineProfile.lite.rawValue
            return EngineProfile(rawValue: raw) ?? .lite
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: profileKey)
        }
    }
}

// MARK: - Games

final class GameStore: ObservableObject {
    @Published private(set) var games: [GameRecord] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        load()
    }

    private func url(for game: GameRecord) -> URL {
        return Paths.games.appendingPathComponent(game.id.uuidString + ".json")
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.games,
                                                                  includingPropertiesForKeys: nil)) ?? []
        var loaded: [GameRecord] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let g = try? decoder.decode(GameRecord.self, from: data) {
                loaded.append(g)
            }
        }
        games = loaded.sorted { $0.date > $1.date }
    }

    /// Inserts or replaces a game and writes it to disk.
    func save(_ game: GameRecord) {
        if let data = try? encoder.encode(game) {
            try? data.write(to: url(for: game), options: .atomic)
        }
        if let i = games.firstIndex(where: { $0.id == game.id }) {
            games[i] = game
        } else {
            games.append(game)
        }
        games.sort { $0.date > $1.date }
    }

    func delete(_ game: GameRecord) {
        try? FileManager.default.removeItem(at: url(for: game))
        games.removeAll { $0.id == game.id }
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { games[$0] }
        for g in targets { delete(g) }
    }

    /// Imports every game found in a PGN text. Returns how many were added.
    @discardableResult
    func importPGN(_ text: String) -> Int {
        let parsed = PGN.parseAll(text)
        for g in parsed { save(g) }
        return parsed.count
    }
}

// MARK: - Python bots

struct PythonBotFile: Identifiable, Hashable {
    var id: String { filename }
    let filename: String
    let path: String

    var name: String {
        return (filename as NSString).deletingPathExtension
    }
}

final class BotStore: ObservableObject {
    @Published private(set) var bots: [PythonBotFile] = []

    init() {
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.bots,
                                                                  includingPropertiesForKeys: nil)) ?? []
        bots = files
            .filter { $0.pathExtension.lowercased() == "py" }
            .map { PythonBotFile(filename: $0.lastPathComponent, path: $0.path) }
            .sorted { $0.filename.lowercased() < $1.filename.lowercased() }
    }

    func importBot(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard url.pathExtension.lowercased() == "py" else {
            throw AnalysisError(message: "Hãy chọn một file .py.")
        }
        let dest = Paths.bots.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        reload()
    }

    func delete(_ bot: PythonBotFile) {
        try? FileManager.default.removeItem(atPath: bot.path)
        reload()
    }
}
