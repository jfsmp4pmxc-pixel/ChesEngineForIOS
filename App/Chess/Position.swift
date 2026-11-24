import Foundation

// MARK: - Basic types

enum Side: Int, Codable {
    case white = 0
    case black = 1

    var opposite: Side { self == .white ? .black : .white }
}

enum PieceType: Int, Codable {
    case pawn = 1, knight, bishop, rook, queen, king

    /// Material value in pawns (king = 0).
    var value: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    var sanLetter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
}

struct Piece: Equatable, Codable {
    let type: PieceType
    let side: Side

    init(_ type: PieceType, _ side: Side) {
        self.type = type
        self.side = side
    }

    init?(fen c: Character) {
        let side: Side = c.isUppercase ? .white : .black
        switch Character(c.lowercased()) {
        case "p": self.init(.pawn, side)
        case "n": self.init(.knight, side)
        case "b": self.init(.bishop, side)
        case "r": self.init(.rook, side)
        case "q": self.init(.queen, side)
        case "k": self.init(.king, side)
        default: return nil
        }
    }

    var fenChar: Character {
        let c: Character
        switch type {
        case .pawn: c = "p"
        case .knight: c = "n"
        case .bishop: c = "b"
        case .rook: c = "r"
        case .queen: c = "q"
        case .king: c = "k"
        }
        return side == .white ? Character(c.uppercased()) : c
    }

    /// Filled glyph for both sides (colour is applied by the view). The text
    /// variation selector stops iOS from rendering the pawn as an emoji.
    var glyph: String {
        let g: String
        switch type {
        case .pawn: g = "\u{265F}"
        case .knight: g = "\u{265E}"
        case .bishop: g = "\u{265D}"
        case .rook: g = "\u{265C}"
        case .queen: g = "\u{265B}"
        case .king: g = "\u{265A}"
        }
        return g + "\u{FE0E}"
    }
}

func squareName(_ sq: Int) -> String {
    let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
    return files[sq % 8] + String(sq / 8 + 1)
}

func squareIndex(_ name: String) -> Int? {
    let chars = Array(name.lowercased())
    guard chars.count == 2,
          let f = "abcdefgh".firstIndex(of: chars[0]),
          let r = "12345678".firstIndex(of: chars[1]) else { return nil }
    let file = "abcdefgh".distance(from: "abcdefgh".startIndex, to: f)
    let rank = "12345678".distance(from: "12345678".startIndex, to: r)
    return rank * 8 + file
}

struct Move: Equatable, Hashable, Codable {
    var from: Int
    var to: Int
    var promotion: PieceType?

    init(from: Int, to: Int, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    var uci: String {
        var s = squareName(from) + squareName(to)
        if let p = promotion {
            s += p.sanLetter.lowercased()
        }
        return s
    }
}

enum PositionStatus: Equatable {
    case ongoing
    case checkmate
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
}

// MARK: - Position

struct Position: Equatable {
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    var board: [Piece?] = Array(repeating: nil, count: 64)
    var turn: Side = .white
    var castleWK = true
    var castleWQ = true
    var castleBK = true
    var castleBQ = true
    var epSquare: Int? = nil
    var halfmove = 0
    var fullmove = 1

    init() {}

    static var start: Position {
        return Position(fen: startFEN) ?? Position()
    }

    // MARK: FEN

    init?(fen: String) {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        let rows = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        for (i, row) in rows.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue, n >= 1, n <= 8 {
                    file += n
                } else if let piece = Piece(fen: ch) {
                    guard file < 8 else { return nil }
                    board[rank * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        switch parts[1] {
        case "w": turn = .white
        case "b": turn = .black
        default: return nil
        }

        castleWK = false
        castleWQ = false
        castleBK = false
        castleBQ = false
        if parts.count > 2 {
            for c in parts[2] {
                switch c {
                case "K": castleWK = true
                case "Q": castleWQ = true
                case "k": castleBK = true
                case "q": castleBQ = true
                default: break
                }
            }
        }
        if parts.count > 3, parts[3] != "-" {
            epSquare = squareIndex(parts[3])
        }
        if parts.count > 4 { halfmove = Int(parts[4]) ?? 0 }
        if parts.count > 5 { fullmove = max(1, Int(parts[5]) ?? 1) }

        // Basic validation: exactly one king per side.
        var whiteKings = 0
        var blackKings = 0
        for p in board {
            if let p = p, p.type == .king {
                if p.side == .white { whiteKings += 1 } else { blackKings += 1 }
            }
        }
        guard whiteKings == 1, blackKings == 1 else { return nil }

        // Drop castling rights that are impossible with the given piece placement.
        if board[4] != Piece(.king, .white) { castleWK = false; castleWQ = false }
        if board[7] != Piece(.rook, .white) { castleWK = false }
        if board[0] != Piece(.rook, .white) { castleWQ = false }
        if board[60] != Piece(.king, .black) { castleBK = false; castleBQ = false }
        if board[63] != Piece(.rook, .black) { castleBK = false }
        if board[56] != Piece(.rook, .black) { castleBQ = false }
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let p = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var castle = ""
        if castleWK { castle += "K" }
        if castleWQ { castle += "Q" }
        if castleBK { castle += "k" }
        if castleBQ { castle += "q" }
        if castle.isEmpty { castle = "-" }
        let ep = epSquare.map { squareName($0) } ?? "-"
        return "\(rows.joined(separator: "/")) \(turn == .white ? "w" : "b") \(castle) \(ep) \(halfmove) \(fullmove)"
    }

    /// Key used for repetition detection (placement, side, castling, ep when capturable).
    var repetitionKey: String {
        let parts = fen.split(separator: " ").map(String.init)
        var ep = "-"
        if let e = epSquare {
            let capturable = legalMoves().contains { m in
                m.to == e && board[m.from]?.type == .pawn
            }
            if capturable { ep = squareName(e) }
        }
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(ep)"
    }

    // MARK: Geometry tables

    private static let knightOffsets: [(Int, Int)] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingOffsets: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let bishopDirs: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let rookDirs: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    // MARK: Attacks

    func kingSquare(_ side: Side) -> Int? {
        for sq in 0..<64 {
            if let p = board[sq], p.type == .king, p.side == side { return sq }
        }
        return nil
    }

    func isAttacked(_ sq: Int, by side: Side) -> Bool {
        return !attackers(of: sq, by: side, removed: [], firstOnly: true).isEmpty
    }

    /// Squares of pieces of `side` attacking `sq`. Squares in `removed` are treated
    /// as empty (used for static exchange evaluation).
    func attackers(of sq: Int, by side: Side, removed: Set<Int>, firstOnly: Bool = false) -> [Int] {
        var result: [Int] = []
        let f = sq % 8
        let r = sq / 8

        // Pawns
        let pr = side == .white ? r - 1 : r + 1
        if pr >= 0 && pr < 8 {
            for df in [-1, 1] {
                let pf = f + df
                if pf >= 0 && pf < 8 {
                    let s = pr * 8 + pf
                    if !removed.contains(s), let p = board[s], p.side == side, p.type == .pawn {
                        result.append(s)
                        if firstOnly { return result }
                    }
                }
            }
        }
        // Knights
        for (df, dr) in Position.knightOffsets {
            let nf = f + df
            let nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                let s = nr * 8 + nf
                if !removed.contains(s), let p = board[s], p.side == side, p.type == .knight {
                    result.append(s)
                    if firstOnly { return result }
                }
            }
        }
        // King
        for (df, dr) in Position.kingOffsets {
            let nf = f + df
            let nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                let s = nr * 8 + nf
                if !removed.contains(s), let p = board[s], p.side == side, p.type == .king {
                    result.append(s)
                    if firstOnly { return result }
                }
            }
        }
        // Sliders
        for (dirs, kind) in [(Position.bishopDirs, PieceType.bishop), (Position.rookDirs, PieceType.rook)] {
            for (df, dr) in dirs {
                var nf = f + df
                var nr = r + dr
                while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    let s = nr * 8 + nf
                    if removed.contains(s) {
                        nf += df
                        nr += dr
                        continue
                    }
                    if let p = board[s] {
                        if p.side == side && (p.type == kind || p.type == .queen) {
                            result.append(s)
                            if firstOnly { return result }
                        }
                        break
                    }
                    nf += df
                    nr += dr
                }
            }
        }
        return result
    }

    var inCheck: Bool {
        guard let k = kingSquare(turn) else { return false }
        return isAttacked(k, by: turn.opposite)
    }

    // MARK: Move generation

    private func addPawnMove(_ from: Int, _ to: Int, promotes: Bool, into moves: inout [Move]) {
        if promotes {
            for t in [PieceType.queen, .rook, .bishop, .knight] {
                moves.append(Move(from: from, to: to, promotion: t))
            }
        } else {
            moves.append(Move(from: from, to: to))
        }
    }

    func pseudoMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for sq in 0..<64 {
            guard let p = board[sq], p.side == turn else { continue }
            let f = sq % 8
            let r = sq / 8
            switch p.type {
            case .pawn:
                let dir = turn == .white ? 1 : -1
                let startRank = turn == .white ? 1 : 6
                let promoRank = turn == .white ? 7 : 0
                let r1 = r + dir
                guard r1 >= 0 && r1 < 8 else { break }
                let to = r1 * 8 + f
                if board[to] == nil {
                    addPawnMove(sq, to, promotes: r1 == promoRank, into: &moves)
                    if r == startRank {
                        let to2 = (r + 2 * dir) * 8 + f
                        if board[to2] == nil {
                            moves.append(Move(from: sq, to: to2))
                        }
                    }
                }
                for df in [-1, 1] {
                    let nf = f + df
                    guard nf >= 0 && nf < 8 else { continue }
                    let t = r1 * 8 + nf
                    if let q = board[t] {
                        if q.side != turn {
                            addPawnMove(sq, t, promotes: r1 == promoRank, into: &moves)
                        }
                    } else if let e = epSquare, e == t {
                        moves.append(Move(from: sq, to: t))
                    }
                }
            case .knight:
                for (df, dr) in Position.knightOffsets {
                    let nf = f + df
                    let nr = r + dr
                    guard nf >= 0 && nf < 8 && nr >= 0 && nr < 8 else { continue }
                    let t = nr * 8 + nf
                    if let q = board[t], q.side == turn { continue }
                    moves.append(Move(from: sq, to: t))
                }
            case .king:
                for (df, dr) in Position.kingOffsets {
                    let nf = f + df
                    let nr = r + dr
                    guard nf >= 0 && nf < 8 && nr >= 0 && nr < 8 else { continue }
                    let t = nr * 8 + nf
                    if let q = board[t], q.side == turn { continue }
                    moves.append(Move(from: sq, to: t))
                }
                addCastling(from: sq, into: &moves)
            case .bishop, .rook, .queen:
                var dirs: [(Int, Int)] = []
                if p.type != .rook { dirs += Position.bishopDirs }
                if p.type != .bishop { dirs += Position.rookDirs }
                for (df, dr) in dirs {
                    var nf = f + df
                    var nr = r + dr
                    while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                        let t = nr * 8 + nf
                        if let q = board[t] {
                            if q.side != turn { moves.append(Move(from: sq, to: t)) }
                            break
                        }
                        moves.append(Move(from: sq, to: t))
                        nf += df
                        nr += dr
                    }
                }
            }
        }
        return moves
    }

    private func addCastling(from sq: Int, into moves: inout [Move]) {
        let enemy = turn.opposite
        if turn == .white && sq == 4 {
            if castleWK, board[5] == nil, board[6] == nil, board[7] == Piece(.rook, .white),
               !isAttacked(4, by: enemy), !isAttacked(5, by: enemy), !isAttacked(6, by: enemy) {
                moves.append(Move(from: 4, to: 6))
            }
            if castleWQ, board[1] == nil, board[2] == nil, board[3] == nil, board[0] == Piece(.rook, .white),
               !isAttacked(4, by: enemy), !isAttacked(3, by: enemy), !isAttacked(2, by: enemy) {
                moves.append(Move(from: 4, to: 2))
            }
        } else if turn == .black && sq == 60 {
            if castleBK, board[61] == nil, board[62] == nil, board[63] == Piece(.rook, .black),
               !isAttacked(60, by: enemy), !isAttacked(61, by: enemy), !isAttacked(62, by: enemy) {
                moves.append(Move(from: 60, to: 62))
            }
            if castleBQ, board[57] == nil, board[58] == nil, board[59] == nil, board[56] == Piece(.rook, .black),
               !isAttacked(60, by: enemy), !isAttacked(59, by: enemy), !isAttacked(58, by: enemy) {
                moves.append(Move(from: 60, to: 58))
            }
        }
    }

    func legalMoves() -> [Move] {
        let mover = turn
        return pseudoMoves().filter { m in
            let next = self.make(m)
            guard let k = next.kingSquare(mover) else { return false }
            return !next.isAttacked(k, by: mover.opposite)
        }
    }

    // MARK: Making moves

    /// Applies a (pseudo-)legal move and returns the resulting position.
    func make(_ m: Move) -> Position {
        var p = self
        guard let piece = board[m.from] else { return p }
        let captured = board[m.to]

        p.board[m.from] = nil
        var placed = piece
        if let promo = m.promotion { placed = Piece(promo, piece.side) }
        p.board[m.to] = placed

        // En passant capture
        if piece.type == .pawn, captured == nil, m.from % 8 != m.to % 8 {
            let capSq = piece.side == .white ? m.to - 8 : m.to + 8
            if capSq >= 0 && capSq < 64 { p.board[capSq] = nil }
        }

        // Castling: move the rook too
        if piece.type == .king && abs(m.to - m.from) == 2 {
            if m.to > m.from {
                p.board[m.from + 1] = p.board[m.from + 3]
                p.board[m.from + 3] = nil
            } else {
                p.board[m.from - 1] = p.board[m.from - 4]
                p.board[m.from - 4] = nil
            }
        }

        // Castling rights
        if piece.type == .king {
            if piece.side == .white { p.castleWK = false; p.castleWQ = false }
            else { p.castleBK = false; p.castleBQ = false }
        }
        for s in [m.from, m.to] {
            switch s {
            case 0: p.castleWQ = false
            case 7: p.castleWK = false
            case 56: p.castleBQ = false
            case 63: p.castleBK = false
            default: break
            }
        }

        p.epSquare = nil
        if piece.type == .pawn && abs(m.to - m.from) == 16 {
            p.epSquare = (m.from + m.to) / 2
        }

        p.halfmove = (piece.type == .pawn || captured != nil) ? 0 : halfmove + 1
        if turn == .black { p.fullmove += 1 }
        p.turn = turn.opposite
        return p
    }

    // MARK: Status

    var hasInsufficientMaterial: Bool {
        var minors: [(PieceType, Int)] = [] // type, square colour
        for sq in 0..<64 {
            guard let p = board[sq] else { continue }
            switch p.type {
            case .king: continue
            case .knight, .bishop:
                minors.append((p.type, ((sq % 8) + (sq / 8)) % 2))
            default:
                return false
            }
        }
        if minors.isEmpty { return true }
        if minors.count == 1 { return true }
        if minors.allSatisfy({ $0.0 == .bishop }) {
            let first = minors[0].1
            return minors.allSatisfy { $0.1 == first }
        }
        return false
    }

    func status() -> PositionStatus {
        if legalMoves().isEmpty {
            return inCheck ? .checkmate : .stalemate
        }
        if hasInsufficientMaterial { return .insufficientMaterial }
        if halfmove >= 100 { return .fiftyMoveRule }
        return .ongoing
    }

    // MARK: Move lookup

    func move(fromUCI uci: String) -> Move? {
        let chars = Array(uci.lowercased())
        guard chars.count >= 4 else { return nil }
        guard let from = squareIndex(String(chars[0...1])),
              let to = squareIndex(String(chars[2...3])) else { return nil }
        var promo: PieceType? = nil
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promo = .queen
            case "r": promo = .rook
            case "b": promo = .bishop
            case "n": promo = .knight
            default: return nil
            }
        }
        return legalMoves().first { $0.from == from && $0.to == to && $0.promotion == promo }
    }

    // MARK: SAN

    private func sanCore(_ m: Move, legal: [Move]) -> String {
        guard let piece = board[m.from] else { return m.uci }
        if piece.type == .king && abs(m.to - m.from) == 2 {
            return m.to > m.from ? "O-O" : "O-O-O"
        }
        let isCapture = board[m.to] != nil || (piece.type == .pawn && m.from % 8 != m.to % 8)
        var s = ""
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        if piece.type == .pawn {
            if isCapture { s += files[m.from % 8] + "x" }
            s += squareName(m.to)
            if let promo = m.promotion { s += "=" + promo.sanLetter }
        } else {
            s += piece.type.sanLetter
            let others = legal.filter { o in
                o.to == m.to && o.from != m.from && board[o.from]?.type == piece.type
            }
            if !others.isEmpty {
                let sameFile = others.contains { $0.from % 8 == m.from % 8 }
                let sameRank = others.contains { $0.from / 8 == m.from / 8 }
                if !sameFile {
                    s += files[m.from % 8]
                } else if !sameRank {
                    s += String(m.from / 8 + 1)
                } else {
                    s += squareName(m.from)
                }
            }
            if isCapture { s += "x" }
            s += squareName(m.to)
        }
        return s
    }

    func san(_ m: Move) -> String {
        let legal = legalMoves()
        var s = sanCore(m, legal: legal)
        let next = make(m)
        if next.inCheck {
            s += next.legalMoves().isEmpty ? "#" : "+"
        }
        return s
    }

    func move(fromSAN text: String) -> Move? {
        var t = text.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "0", with: "O")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "+#!?"))
        guard !t.isEmpty else { return nil }
        let legal = legalMoves()

        func lenient(_ s: String) -> String {
            return s.replacingOccurrences(of: "x", with: "")
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }

        // Exact SAN first (so "bxc3" is the pawn and "Bxc3" the bishop), then lenient.
        for m in legal where sanCore(m, legal: legal) == t { return m }
        let target = lenient(t)
        for m in legal where lenient(sanCore(m, legal: legal)) == target { return m }
        // Long algebraic / UCI style fallback (e2e4, e7e8q)
        if let m = move(fromUCI: t) { return m }
        return nil
    }
}
