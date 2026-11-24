import Foundation
import SwiftUI

// MARK: - Evaluation

/// Engine evaluation from White's point of view.
struct Eval: Codable, Equatable {
    var cp: Int
    var mate: Int?   // positive: White mates in n; negative: Black mates in n

    static let draw = Eval(cp: 0, mate: nil)

    /// Win probability for White in percent (Lichess logistic model).
    var whiteWinPercent: Double {
        if let m = mate { return m > 0 ? 100 : 0 }
        if abs(cp) >= 10000 { return cp > 0 ? 100 : 0 }
        let c = Double(max(-1000, min(1000, cp)))
        return 50 + 50 * (2 / (1 + exp(-0.00368208 * c)) - 1)
    }

    func winPercent(for side: Side) -> Double {
        return side == .white ? whiteWinPercent : 100 - whiteWinPercent
    }

    var display: String {
        if let m = mate { return m > 0 ? "M\(m)" : "-M\(abs(m))" }
        if abs(cp) >= 10000 { return cp > 0 ? "1-0" : "0-1" }
        return String(format: "%+.1f", Double(cp) / 100.0)
    }

    /// Score in pawns clamped for drawing the graph.
    var graphValue: Double {
        if mate != nil || abs(cp) >= 10000 { return whiteWinPercent >= 50 ? 10 : -10 }
        return max(-10, min(10, Double(cp) / 100.0))
    }

    static func fromWhitePOV(line: EngineLine, turn: Side) -> Eval {
        let sign = turn == .white ? 1 : -1
        if let m = line.mate {
            return Eval(cp: sign * (m > 0 ? 9000 : -9000), mate: sign * m)
        }
        return Eval(cp: sign * (line.cp ?? 0), mate: nil)
    }
}

// MARK: - Move classification

enum MoveClass: String, Codable, CaseIterable {
    case brilliant, great, best, excellent, good, book, inaccuracy, mistake, blunder, forced

    var label: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .great: return "Great"
        case .best: return "Best"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .book: return "Book"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .forced: return "Forced"
        }
    }

    var symbol: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .best: return "★"
        case .excellent: return "✓"
        case .good: return "•"
        case .book: return "📖"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        case .forced: return "→"
        }
    }

    var color: Color {
        switch self {
        case .brilliant: return Color(red: 0.11, green: 0.73, blue: 0.70)
        case .great: return Color(red: 0.36, green: 0.55, blue: 0.80)
        case .best: return Color(red: 0.50, green: 0.70, blue: 0.20)
        case .excellent: return Color(red: 0.55, green: 0.72, blue: 0.30)
        case .good: return Color(red: 0.62, green: 0.66, blue: 0.45)
        case .book: return Color(red: 0.66, green: 0.52, blue: 0.38)
        case .inaccuracy: return Color(red: 0.95, green: 0.75, blue: 0.15)
        case .mistake: return Color(red: 0.95, green: 0.55, blue: 0.15)
        case .blunder: return Color(red: 0.85, green: 0.20, blue: 0.20)
        case .forced: return Color.gray
        }
    }

    /// Order used for the summary table.
    static let summaryOrder: [MoveClass] = [
        .brilliant, .great, .best, .excellent, .good, .book, .inaccuracy, .mistake, .blunder
    ]
}

// MARK: - Review models

struct MoveReview: Codable, Equatable {
    var ply: Int                 // 0-based index of the move
    var san: String
    var uci: String
    var classification: MoveClass
    var lossPercent: Double      // win-probability points lost versus the best move
    var accuracy: Double         // 0...100
    var bestUCI: String?
    var bestSAN: String?
}

struct GameReview: Codable, Equatable {
    var moves: [MoveReview]
    var evals: [Eval]            // one per position, count == moves.count + 1
    var whiteAccuracy: Double
    var blackAccuracy: Double
    var whiteCounts: [String: Int]
    var blackCounts: [String: Int]
    var opening: String?
    var engine: String
    var depth: Int
    var generatedAt: Date
}

struct AnalysisError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Static exchange evaluation

extension Position {
    /// Net material (in pawns) that `side` can win by starting a capture sequence on `sq`.
    func see(on sq: Int, by side: Side) -> Int {
        guard let target = board[sq] else { return 0 }

        func value(_ t: PieceType) -> Int { return t == .king ? 100 : t.value }
        func cheapest(_ list: [Int]) -> Int? {
            return list.min(by: { a, b in
                value(self.board[a]?.type ?? .king) < value(self.board[b]?.type ?? .king)
            })
        }

        var removed = Set<Int>()
        guard let first = cheapest(attackers(of: sq, by: side, removed: removed)) else { return 0 }

        var gain: [Int] = [value(target.type)]
        removed.insert(first)
        var onSquare = value(board[first]?.type ?? .pawn)
        var attacker = side.opposite
        var d = 0

        while d < 30 {
            guard let next = cheapest(attackers(of: sq, by: attacker, removed: removed)) else { break }
            d += 1
            gain.append(onSquare - gain[d - 1])
            removed.insert(next)
            onSquare = value(board[next]?.type ?? .pawn)
            attacker = attacker.opposite
        }
        while d > 0 {
            gain[d - 1] = -max(-gain[d - 1], gain[d])
            d -= 1
        }
        return max(0, gain[0])
    }
}

// MARK: - Analyzer

enum ReviewAnalyzer {
    private struct PositionEval {
        var eval: Eval
        var best: String?
        var second: Eval?
    }

    static func accuracy(forLoss loss: Double) -> Double {
        let a = 103.1668 * exp(-0.04354 * loss) - 3.1669
        return max(0, min(100, a))
    }

    private static func combine(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 100 }
        let mean = values.reduce(0, +) / Double(values.count)
        let inverseSum = values.reduce(0.0) { partial, v in partial + 1 / max(v, 1) }
        let harmonic = Double(values.count) / inverseSum
        return (mean + harmonic) / 2
    }

    static func analyze(record: GameRecord,
                        profile: EngineProfile,
                        progress: @escaping (Double) async -> Void) async throws -> GameReview {
        let replay = record.replay()
        let positions = replay.positions
        let moves = replay.moves
        guard !moves.isEmpty else { throw AnalysisError(message: "This game has no moves to review.") }

        // 1. Evaluate every position once.
        var evals: [PositionEval] = []
        for (i, pos) in positions.enumerated() {
            try Task.checkCancellation()
            switch pos.status() {
            case .checkmate:
                let cp = pos.turn == .white ? -10000 : 10000
                evals.append(PositionEval(eval: Eval(cp: cp, mate: nil), best: nil, second: nil))
            case .stalemate, .insufficientMaterial, .fiftyMoveRule:
                evals.append(PositionEval(eval: .draw, best: nil, second: nil))
            case .ongoing:
                let result = await StockfishEngine.shared.search(
                    fen: pos.fen,
                    depth: profile.analysisDepth,
                    movetimeMs: profile.analysisMaxMillis,
                    multiPV: 2,
                    strength: .full,
                    profile: profile)
                try Task.checkCancellation()
                guard let r = result, let top = r.lines.first else {
                    throw AnalysisError(message: StockfishEngine.shared.startupError
                                        ?? "Stockfish did not return an evaluation.")
                }
                let e = Eval.fromWhitePOV(line: top, turn: pos.turn)
                let s = r.lines.count > 1 ? Eval.fromWhitePOV(line: r.lines[1], turn: pos.turn) : nil
                evals.append(PositionEval(eval: e, best: r.bestMove ?? top.pv.first, second: s))
            }
            await progress(Double(i + 1) / Double(positions.count))
        }

        // 2. Classify each move.
        let ucis = moves.map { $0.uci }
        let bookPlies = Openings.bookPlies(for: ucis)
        var reviews: [MoveReview] = []
        var whiteAcc: [Double] = []
        var blackAcc: [Double] = []
        var whiteCounts: [String: Int] = [:]
        var blackCounts: [String: Int] = [:]

        for (i, move) in moves.enumerated() {
            let pos = positions[i]
            let mover = pos.turn
            let before = evals[i]
            let after = evals[i + 1]
            let winBefore = before.eval.winPercent(for: mover)
            let winAfter = after.eval.winPercent(for: mover)
            let playedBest = before.best == move.uci
            let loss = playedBest ? 0 : max(0, winBefore - winAfter)
            let ep = loss / 100
            let legalCount = pos.legalMoves().count

            var cls: MoveClass
            if legalCount == 1 {
                cls = .forced
            } else if i < bookPlies {
                cls = .book
            } else {
                if playedBest || ep <= 0.005 { cls = .best }
                else if ep <= 0.02 { cls = .excellent }
                else if ep <= 0.05 { cls = .good }
                else if ep <= 0.10 { cls = .inaccuracy }
                else if ep <= 0.20 { cls = .mistake }
                else { cls = .blunder }

                if cls == .best || cls == .excellent {
                    if isBrilliant(pos: pos, move: move, loss: loss, winBefore: winBefore, winAfter: winAfter) {
                        cls = .brilliant
                    } else if playedBest, let second = before.second,
                              isGreat(pos: pos, move: move, previous: i > 0 ? moves[i - 1] : nil,
                                      winBefore: winBefore, secondWin: second.winPercent(for: mover)) {
                        cls = .great
                    }
                }
            }

            let acc = accuracy(forLoss: loss)
            var bestSAN: String? = nil
            if let b = before.best, let bm = pos.move(fromUCI: b) { bestSAN = pos.san(bm) }

            reviews.append(MoveReview(ply: i,
                                      san: replay.sans[i],
                                      uci: move.uci,
                                      classification: cls,
                                      lossPercent: loss,
                                      accuracy: acc,
                                      bestUCI: before.best,
                                      bestSAN: bestSAN))

            if mover == .white {
                whiteAcc.append(acc)
                whiteCounts[cls.rawValue, default: 0] += 1
            } else {
                blackAcc.append(acc)
                blackCounts[cls.rawValue, default: 0] += 1
            }
        }

        return GameReview(moves: reviews,
                          evals: evals.map { $0.eval },
                          whiteAccuracy: combine(whiteAcc),
                          blackAccuracy: combine(blackAcc),
                          whiteCounts: whiteCounts,
                          blackCounts: blackCounts,
                          opening: Openings.name(for: ucis),
                          engine: "Stockfish 17.1 (\(profile.title))",
                          depth: profile.analysisDepth,
                          generatedAt: Date())
    }

    // MARK: Heuristics

    /// A good move that gives up material (a real sacrifice) without worsening the position.
    private static func isBrilliant(pos: Position, move: Move, loss: Double,
                                    winBefore: Double, winAfter: Double) -> Bool {
        guard loss <= 2, move.promotion == nil, winAfter >= 45, winBefore < 92 else { return false }
        guard let piece = pos.board[move.from], piece.type != .pawn, piece.type != .king else { return false }
        let captured = pos.board[move.to]?.type.value ?? 0
        let next = pos.make(move)
        let lost = next.see(on: move.to, by: next.turn)
        return lost - captured >= 2
    }

    /// The only move that keeps the position, when the alternative is clearly worse.
    private static func isGreat(pos: Position, move: Move, previous: Move?,
                                winBefore: Double, secondWin: Double) -> Bool {
        guard winBefore < 95, winBefore - secondWin >= 15 else { return false }
        // Plain recaptures are not "great".
        if let p = previous, p.to == move.to, pos.board[move.to] != nil { return false }
        return true
    }
}
