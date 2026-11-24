import Foundation

// MARK: - Stored game

/// A finished or in-progress game as persisted on disk (moves are stored as UCI).
struct GameRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var white: String = "White"
    var black: String = "Black"
    var event: String = "Casual game"
    var date: Date = Date()
    var result: String = "*"          // "1-0", "0-1", "1/2-1/2", "*"
    var termination: String = ""      // e.g. "Checkmate", "Resignation"
    var startFEN: String = Position.startFEN
    var moves: [String] = []          // UCI
    var review: GameReview? = nil

    static func == (lhs: GameRecord, rhs: GameRecord) -> Bool {
        return lhs.id == rhs.id && lhs.moves == rhs.moves && lhs.result == rhs.result
            && lhs.review?.generatedAt == rhs.review?.generatedAt
    }

    /// Positions after each move (index 0 is the start position) and the parsed moves.
    func replay() -> (positions: [Position], moves: [Move], sans: [String]) {
        var pos = Position(fen: startFEN) ?? Position.start
        var positions = [pos]
        var parsed: [Move] = []
        var sans: [String] = []
        for uci in moves {
            guard let m = pos.move(fromUCI: uci) else { break }
            sans.append(pos.san(m))
            pos = pos.make(m)
            positions.append(pos)
            parsed.append(m)
        }
        return (positions, parsed, sans)
    }
}

// MARK: - Live game

/// Mutable game state used while playing and reviewing.
struct GameSession {
    private(set) var startFEN: String
    private(set) var positions: [Position]
    private(set) var moves: [Move] = []
    private(set) var sans: [String] = []
    var result: String = "*"
    var termination: String = ""

    init(startFEN: String = Position.startFEN) {
        self.startFEN = startFEN
        self.positions = [Position(fen: startFEN) ?? Position.start]
    }

    init(record: GameRecord) {
        self.init(startFEN: record.startFEN)
        let r = record.replay()
        positions = r.positions
        moves = r.moves
        sans = r.sans
        result = record.result
        termination = record.termination
    }

    var position: Position { positions[positions.count - 1] }
    var isOver: Bool { result != "*" }

    var lastMove: Move? { moves.last }

    mutating func play(_ move: Move) {
        guard !isOver else { return }
        let pos = position
        sans.append(pos.san(move))
        moves.append(move)
        positions.append(pos.make(move))
        evaluateEnd()
    }

    mutating func undo(plies: Int = 1) {
        let n = min(plies, moves.count)
        guard n > 0 else { return }
        moves.removeLast(n)
        sans.removeLast(n)
        positions.removeLast(n)
        result = "*"
        termination = ""
        evaluateEnd()
    }

    mutating func resign(_ side: Side) {
        guard !isOver else { return }
        result = side == .white ? "0-1" : "1-0"
        termination = "Resignation"
    }

    mutating func agreeDraw() {
        guard !isOver else { return }
        result = "1/2-1/2"
        termination = "Draw agreed"
    }

    private mutating func evaluateEnd() {
        let pos = position
        switch pos.status() {
        case .checkmate:
            result = pos.turn == .white ? "0-1" : "1-0"
            termination = "Checkmate"
        case .stalemate:
            result = "1/2-1/2"
            termination = "Stalemate"
        case .insufficientMaterial:
            result = "1/2-1/2"
            termination = "Insufficient material"
        case .fiftyMoveRule:
            result = "1/2-1/2"
            termination = "Fifty-move rule"
        case .ongoing:
            if isThreefold {
                result = "1/2-1/2"
                termination = "Threefold repetition"
            }
        }
    }

    private var isThreefold: Bool {
        let key = position.repetitionKey
        var count = 0
        for p in positions where p.repetitionKey == key { count += 1 }
        return count >= 3
    }

    func record(white: String, black: String, event: String = "Casual game") -> GameRecord {
        var r = GameRecord()
        r.white = white
        r.black = black
        r.event = event
        r.result = result
        r.termination = termination
        r.startFEN = startFEN
        r.moves = moves.map { $0.uci }
        return r
    }
}

// MARK: - PGN

enum PGN {
    static func export(_ g: GameRecord) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy.MM.dd"
        var out = ""
        out += "[Event \"\(escape(g.event))\"]\n"
        out += "[Site \"Chess Engine for iOS\"]\n"
        out += "[Date \"\(df.string(from: g.date))\"]\n"
        out += "[Round \"-\"]\n"
        out += "[White \"\(escape(g.white))\"]\n"
        out += "[Black \"\(escape(g.black))\"]\n"
        out += "[Result \"\(g.result)\"]\n"
        if !g.termination.isEmpty { out += "[Termination \"\(escape(g.termination))\"]\n" }
        if g.startFEN != Position.startFEN {
            out += "[SetUp \"1\"]\n[FEN \"\(g.startFEN)\"]\n"
        }
        out += "\n"

        let r = g.replay()
        var tokens: [String] = []
        for (i, san) in r.sans.enumerated() {
            let pos = r.positions[i]
            if pos.turn == .white {
                tokens.append("\(pos.fullmove).")
            } else if i == 0 {
                tokens.append("\(pos.fullmove)...")
            }
            tokens.append(san)
        }
        tokens.append(g.result)

        // Wrap at ~80 columns.
        var line = ""
        for t in tokens {
            if line.count + t.count + 1 > 80 {
                out += line + "\n"
                line = t
            } else {
                line += line.isEmpty ? t : " " + t
            }
        }
        out += line + "\n"
        return out
    }

    private static func escape(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Splits a PGN file into games and parses each one. Unparseable games are skipped.
    static func parseAll(_ text: String) -> [GameRecord] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var chunks: [[String]] = []
        var current: [String] = []
        var sawMoves = false
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            let isHeader = s.hasPrefix("[") && s.contains("\"")
            if isHeader && sawMoves {
                chunks.append(current)
                current = []
                sawMoves = false
            }
            if !isHeader && !s.trimmingCharacters(in: .whitespaces).isEmpty { sawMoves = true }
            current.append(s)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.compactMap { parseOne($0.joined(separator: "\n")) }
    }

    static func parseOne(_ text: String) -> GameRecord? {
        var headers: [String: String] = [:]
        var body = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("["), s.hasSuffix("]"), let q1 = s.firstIndex(of: "\""), let q2 = s.lastIndex(of: "\""), q1 < q2 {
                let key = s.dropFirst().prefix(while: { $0 != " " })
                let value = s[s.index(after: q1)..<q2]
                headers[String(key)] = String(value)
            } else {
                body += s + " "
            }
        }

        var game = GameRecord()
        game.white = headers["White"] ?? "White"
        game.black = headers["Black"] ?? "Black"
        game.event = headers["Event"] ?? "Imported game"
        game.termination = headers["Termination"] ?? ""
        if let d = headers["Date"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy.MM.dd"
            if let date = df.date(from: d) { game.date = date }
        }
        if let fen = headers["FEN"], Position(fen: fen) != nil {
            game.startFEN = fen
        }

        var pos = Position(fen: game.startFEN) ?? Position.start
        var moves: [String] = []
        var result = headers["Result"] ?? "*"

        for token in tokenize(body) {
            if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) {
                result = token
                break
            }
            guard let m = pos.move(fromSAN: token) else {
                // Stop at the first move we cannot understand but keep what we have.
                break
            }
            moves.append(m.uci)
            pos = pos.make(m)
        }
        guard !moves.isEmpty || headers["FEN"] != nil else { return nil }
        game.moves = moves
        game.result = result
        return game
    }

    /// Removes comments, variations, NAGs and move numbers.
    private static func tokenize(_ body: String) -> [String] {
        var cleaned = ""
        var braceDepth = 0
        var parenDepth = 0
        var inLineComment = false
        for ch in body {
            if inLineComment {
                if ch == "\n" { inLineComment = false }
                continue
            }
            if braceDepth > 0 {
                if ch == "}" { braceDepth -= 1 }
                continue
            }
            switch ch {
            case "{": braceDepth += 1
            case ";": inLineComment = true
            case "(": parenDepth += 1
            case ")": parenDepth = max(0, parenDepth - 1)
            default:
                if parenDepth == 0 { cleaned.append(ch) }
            }
        }
        var tokens: [String] = []
        for raw in cleaned.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            var t = String(raw)
            if t.hasPrefix("$") { continue }
            // Strip a leading move number such as "12." or "12..."
            if let dot = t.firstIndex(of: "."), t[t.startIndex..<dot].allSatisfy({ $0.isNumber }) {
                t = String(t[t.index(after: dot)...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            if t.isEmpty { continue }
            tokens.append(t)
        }
        return tokens
    }
}
