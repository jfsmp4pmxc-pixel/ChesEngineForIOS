import Foundation

// MARK: - Profiles and strength

/// Analysis / play profile. "Lite" is lighter on CPU and battery, "Full" searches deeper.
enum EngineProfile: String, CaseIterable, Codable, Identifiable {
    case lite
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lite: return "Lite"
        case .full: return "Full"
        }
    }

    var detail: String {
        switch self {
        case .lite: return "Độ sâu 12, 1 luồng, hash 16 MB. Nhanh và tiết kiệm pin."
        case .full: return "Độ sâu 18, nhiều luồng, hash 64 MB. Mạnh hơn nhưng phân tích chậm hơn."
        }
    }

    var analysisDepth: Int { self == .lite ? 12 : 18 }
    var analysisMaxMillis: Int { self == .lite ? 1500 : 4000 }
    var hashMB: Int { self == .lite ? 16 : 64 }
    var threads: Int {
        if self == .lite { return 1 }
        return max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
    }
}

enum Strength: Equatable {
    case elo(Int)      // UCI_LimitStrength + UCI_Elo (1320...3190)
    case skill(Int)    // Skill Level 0...20
    case full
}

struct PlayLevel: Identifiable, Equatable {
    let id: Int
    let name: String
    let strength: Strength
    let depth: Int?
    let movetimeMs: Int

    static let all: [PlayLevel] = [
        PlayLevel(id: 0, name: "Mới học", strength: .skill(0), depth: 1, movetimeMs: 100),
        PlayLevel(id: 1, name: "Giải trí (~1320)", strength: .elo(1320), depth: nil, movetimeMs: 300),
        PlayLevel(id: 2, name: "Câu lạc bộ (~1600)", strength: .elo(1600), depth: nil, movetimeMs: 500),
        PlayLevel(id: 3, name: "Trung cấp (~1900)", strength: .elo(1900), depth: nil, movetimeMs: 700),
        PlayLevel(id: 4, name: "Nâng cao (~2200)", strength: .elo(2200), depth: nil, movetimeMs: 1000),
        PlayLevel(id: 5, name: "Chuyên gia (~2500)", strength: .elo(2500), depth: nil, movetimeMs: 1200),
        PlayLevel(id: 6, name: "Đại sư (~2800)", strength: .elo(2800), depth: nil, movetimeMs: 1500),
        PlayLevel(id: 7, name: "Tối đa", strength: .full, depth: nil, movetimeMs: 2000)
    ]
}

// MARK: - Results

struct EngineLine {
    var multipv: Int = 1
    var depth: Int = 0
    var cp: Int? = nil       // side-to-move perspective
    var mate: Int? = nil     // side-to-move perspective
    var pv: [String] = []
}

struct SearchResult {
    var bestMove: String?
    var lines: [EngineLine]
}

// MARK: - Engine

/// Wraps the embedded Stockfish. Stockfish keeps global state, so there is a single
/// instance for the whole process and searches are executed one at a time.
final class StockfishEngine {
    static let shared = StockfishEngine()

    /// Name shown in the interface.
    static let versionName = "Stockfish 19"

    private let workQueue = DispatchQueue(label: "chess.stockfish.search", qos: .userInitiated)
    private var started = false
    private var failure: String?
    private var applied: [String: String] = [:]

    private init() {}

    var startupError: String? { failure }

    // MARK: Lifecycle

    private func readLine(timeoutMs: Int) -> ReadResult {
        var buf = [CChar](repeating: 0, count: 16384)
        let n = sf_read(&buf, Int32(buf.count), Int32(timeoutMs))
        if n == -2 { return .timeout }
        if n < 0 { return .closed }
        return .line(String(cString: buf))
    }

    private enum ReadResult {
        case line(String)
        case timeout
        case closed
    }

    private func waitFor(_ token: String, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            switch readLine(timeoutMs: 500) {
            case .line(let l):
                if l.hasPrefix(token) { return true }
            case .timeout:
                continue
            case .closed:
                return false
            }
        }
        return false
    }

    /// Must be called on `workQueue`.
    private func ensureStarted() -> Bool {
        if started { return true }
        if failure != nil { return false }

        let netsDir = Bundle.main.bundlePath + "/nets"
        let nets = (try? FileManager.default.contentsOfDirectory(atPath: netsDir))?.filter { $0.hasSuffix(".nnue") } ?? []
        guard nets.count >= 1 else {
            failure = "Thiếu file mạng nơ-ron Stockfish (.nnue) trong ứng dụng."
            return false
        }

        let rc = sf_start(netsDir + "/stockfish")
        guard rc >= 0 else {
            failure = "Không khởi động được luồng Stockfish (mã \(rc))."
            return false
        }

        sf_send("uci")
        guard waitFor("uciok", seconds: 20) else {
            failure = "Stockfish không phản hồi bước bắt tay UCI."
            return false
        }
        sf_send("isready")
        guard waitFor("readyok", seconds: 60) else {
            failure = "Stockfish chưa sẵn sàng."
            return false
        }
        started = true
        return true
    }

    private func setOption(_ name: String, _ value: String) {
        if applied[name] == value { return }
        sf_send("setoption name \(name) value \(value)")
        applied[name] = value
    }

    // MARK: Searching

    func stop() {
        sf_send("stop")
    }

    /// Blocking search. Call only from a background thread (or use `search`).
    func searchSync(fen: String,
                    depth: Int?,
                    movetimeMs: Int?,
                    multiPV: Int,
                    strength: Strength,
                    profile: EngineProfile) -> SearchResult? {
        // Stockfish 19 ends the whole process when it is given an invalid position,
        // so never send it one.
        guard let checked = Position(fen: fen), checked.isSafeForEngine else { return nil }
        guard ensureStarted() else { return nil }

        setOption("Threads", String(profile.threads))
        setOption("Hash", String(profile.hashMB))
        setOption("MultiPV", String(max(1, multiPV)))
        switch strength {
        case .elo(let e):
            setOption("UCI_LimitStrength", "true")
            setOption("UCI_Elo", String(e))
            setOption("Skill Level", "20")
        case .skill(let s):
            setOption("UCI_LimitStrength", "false")
            setOption("Skill Level", String(s))
        case .full:
            setOption("UCI_LimitStrength", "false")
            setOption("Skill Level", "20")
        }

        sf_send("position fen \(fen)")
        var go = "go"
        if let d = depth { go += " depth \(d)" }
        if let t = movetimeMs { go += " movetime \(t)" }
        if depth == nil && movetimeMs == nil { go += " movetime 1000" }
        sf_send(go)

        var lines: [Int: EngineLine] = [:]
        var best: String? = nil
        var deadline = Date().addingTimeInterval(Double((movetimeMs ?? 5000)) / 1000.0 + 20)
        var stopSent = false

        loop: while true {
            switch readLine(timeoutMs: 500) {
            case .timeout:
                if !stopSent && Date() > deadline {
                    sf_send("stop")
                    stopSent = true
                    deadline = Date().addingTimeInterval(10)
                } else if stopSent && Date() > deadline {
                    return nil
                }
            case .closed:
                return nil
            case .line(let l):
                if l.hasPrefix("bestmove") {
                    let parts = l.split(separator: " ")
                    if parts.count >= 2, parts[1] != "(none)" { best = String(parts[1]) }
                    break loop
                } else if l.hasPrefix("info "), let info = StockfishEngine.parseInfo(l) {
                    lines[info.multipv] = info
                }
            }
        }

        let sorted = lines.keys.sorted().compactMap { lines[$0] }
        return SearchResult(bestMove: best, lines: sorted)
    }

    func search(fen: String,
                depth: Int?,
                movetimeMs: Int?,
                multiPV: Int = 1,
                strength: Strength = .full,
                profile: EngineProfile) async -> SearchResult? {
        return await withCheckedContinuation { (cont: CheckedContinuation<SearchResult?, Never>) in
            workQueue.async {
                let r = self.searchSync(fen: fen, depth: depth, movetimeMs: movetimeMs,
                                        multiPV: multiPV, strength: strength, profile: profile)
                cont.resume(returning: r)
            }
        }
    }

    /// Reports whether the engine can start (loads it on first use).
    func checkAvailability() async -> String? {
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            workQueue.async {
                _ = self.ensureStarted()
                cont.resume(returning: self.failure)
            }
        }
    }

    // MARK: Parsing

    static func parseInfo(_ line: String) -> EngineLine? {
        let t = line.split(separator: " ").map(String.init)
        guard let pvIndex = t.firstIndex(of: "pv"), pvIndex + 1 < t.count else { return nil }
        var info = EngineLine()
        var i = 1
        while i < pvIndex {
            switch t[i] {
            case "depth":
                if i + 1 < t.count { info.depth = Int(t[i + 1]) ?? info.depth }
                i += 2
            case "multipv":
                if i + 1 < t.count { info.multipv = Int(t[i + 1]) ?? 1 }
                i += 2
            case "score":
                if i + 2 < t.count {
                    if t[i + 1] == "cp" { info.cp = Int(t[i + 2]) }
                    else if t[i + 1] == "mate" { info.mate = Int(t[i + 2]) }
                }
                i += 3
            default:
                i += 1
            }
        }
        info.pv = Array(t[(pvIndex + 1)...])
        guard info.cp != nil || info.mate != nil else { return nil }
        return info
    }
}

// MARK: - Input safety

extension Position {
    /// True when Stockfish will accept the position: one king per side, no pawns on the
    /// first or last rank, and the side that is not to move is not in check.
    var isSafeForEngine: Bool {
        var kings = [0, 0]
        for sq in 0..<64 {
            guard let p = board[sq] else { continue }
            if p.type == .king { kings[p.side.rawValue] += 1 }
            if p.type == .pawn && (sq < 8 || sq >= 56) { return false }
        }
        guard kings[0] == 1, kings[1] == 1 else { return false }
        if let k = kingSquare(turn.opposite), isAttacked(k, by: turn) { return false }
        return true
    }
}
