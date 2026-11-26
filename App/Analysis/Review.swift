import Foundation
import SwiftUI

// MARK: - Evaluation

/// Engine evaluation from White's point of view.
struct Eval: Codable, Equatable {
    var cp: Int
    var mate: Int?   // positive: White mates in n; negative: Black mates in n

    static let draw = Eval(cp: 0, mate: nil)

    /// Rating at which the logistic curve is not adjusted.
    static let referenceRating = 1500

    /// Win probability for White in percent: P = 1 / (1 + exp(-k * cp)). Mate scores are
    /// never run through the curve. A lower rating makes the curve steeper, which forgives
    /// small slips more (k scales with the distance from 1500).
    func whiteWinPercentAdjusted(rating: Int) -> Double {
        if let m = mate { return m > 0 ? 100 : 0 }
        if abs(cp) >= 10000 { return cp > 0 ? 100 : 0 }
        let k = 0.00368208 * (1 + Double(Eval.referenceRating - rating) / 10000)
        return 100 / (1 + exp(-k * Double(cp)))
    }

    var whiteWinPercent: Double { return whiteWinPercentAdjusted(rating: Eval.referenceRating) }

    func winPercent(for side: Side, rating: Int = Eval.referenceRating) -> Double {
        let white = whiteWinPercentAdjusted(rating: rating)
        return side == .white ? white : 100 - white
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
    case brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder, forced

    var label: String {
        switch self {
        case .brilliant: return "Thiên tài"
        case .great: return "Tuyệt vời"
        case .best: return "Tốt nhất"
        case .excellent: return "Xuất sắc"
        case .good: return "Tốt"
        case .book: return "Khai cuộc"
        case .inaccuracy: return "Thiếu chính xác"
        case .mistake: return "Sai lầm"
        case .miss: return "Cơ hội bị bỏ lỡ"
        case .blunder: return "Sai lầm nghiêm trọng"
        case .forced: return "Bắt buộc"
        }
    }

    /// Completes the sentence "<move> ..." in the review header.
    var phrase: String {
        switch self {
        case .brilliant: return "là nước đi thiên tài"
        case .great: return "là nước đi tuyệt vời"
        case .best: return "là nước đi tốt nhất"
        case .excellent: return "là nước đi xuất sắc"
        case .good: return "là nước đi tốt"
        case .book: return "là nước khai cuộc"
        case .inaccuracy: return "là nước đi thiếu chính xác"
        case .mistake: return "là một sai lầm"
        case .miss: return "là một cơ hội bị bỏ lỡ"
        case .blunder: return "là sai lầm nghiêm trọng"
        case .forced: return "là nước đi bắt buộc"
        }
    }

    /// Name of the badge image in the asset catalog.
    var iconName: String { return "class_" + rawValue }

    /// Text drawn only if the badge image is missing.
    var symbol: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .best: return "★"
        case .excellent: return "+"
        case .good: return "✓"
        case .book: return "B"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .miss: return "✕"
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
        case .miss: return Color(red: 0.88, green: 0.42, blue: 0.36)
        case .blunder: return Color(red: 0.85, green: 0.20, blue: 0.20)
        case .forced: return Color.gray
        }
    }

    /// Order used for the summary table.
    static let summaryOrder: [MoveClass] = [
        .brilliant, .great, .best, .excellent, .good, .book, .inaccuracy, .mistake, .miss, .blunder
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

/// Engine verdict on one position, from White's point of view.
struct PositionEval {
    var eval: Eval
    var best: String?      // engine's best move (UCI)
    var second: Eval?      // score of the second-best line
}

/// Result of classifying one move.
struct ClassifiedMove {
    var classification: MoveClass
    var epl: Double                 // expected points lost, 0...1
    var accuracy: Double            // 0...100
    var bestUCI: String?
    var bestSAN: String?
    /// False for forced and book moves, which are left out of the accuracy average.
    var countsTowardAverage: Bool
}

enum ReviewAnalyzer {
    /// Accuracy of one move from its expected points lost (0...1).
    static func accuracy(forEPL epl: Double) -> Double {
        let a = 103.1668 * exp(-4.0 * epl) - 3.1668
        return max(0, min(100, a))
    }

    /// Comparisons on expected-points thresholds are inclusive, with a small tolerance
    /// so floating-point noise cannot push a move into the next bucket.
    private static func atMost(_ value: Double, _ limit: Double) -> Bool {
        return value <= limit + 1e-6
    }

    /// Great has a branch that fires when a move throws away a big advantage. It is what
    /// the reference classification specifies, but it labels the player's own blunder
    /// "great", so it can be switched off here.
    private static let greatIncludesLostAdvantage = true

    private static func combine(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 100 }
        let mean = values.reduce(0, +) / Double(values.count)
        let inverseSum = values.reduce(0.0) { partial, v in partial + 1 / max(v, 1) }
        let harmonic = Double(values.count) / inverseSum
        return (mean + harmonic) / 2
    }

    // MARK: Whole game

    static func analyze(record: GameRecord,
                        profile: EngineProfile,
                        rating: Int = Eval.referenceRating,
                        progress: @escaping (Double) async -> Void) async throws -> GameReview {
        let replay = record.replay()
        let positions = replay.positions
        let moves = replay.moves
        guard !moves.isEmpty else { throw AnalysisError(message: "Ván cờ này chưa có nước đi nào để phân tích.") }

        // 1. Evaluate every position once.
        var evals: [PositionEval] = []
        for (i, pos) in positions.enumerated() {
            try Task.checkCancellation()
            evals.append(try await evaluate(pos, profile: profile))
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
        // Expected points the opponent lost with their previous move (0 if it was forced or book).
        var opponentLastLoss = 0.0

        for (i, move) in moves.enumerated() {
            let c = try await classify(position: positions[i],
                                       move: move,
                                       next: positions[i + 1],
                                       before: evals[i],
                                       after: evals[i + 1],
                                       isBook: i < bookPlies,
                                       previous: i > 0 ? (positions[i - 1], moves[i - 1]) : nil,
                                       opponentLastLoss: opponentLastLoss,
                                       rating: rating,
                                       profile: profile)
            opponentLastLoss = c.countsTowardAverage ? c.epl : 0

            reviews.append(MoveReview(ply: i,
                                      san: replay.sans[i],
                                      uci: move.uci,
                                      classification: c.classification,
                                      lossPercent: c.epl * 100,
                                      accuracy: c.accuracy,
                                      bestUCI: c.bestUCI,
                                      bestSAN: c.bestSAN))

            if positions[i].turn == .white {
                if c.countsTowardAverage { whiteAcc.append(c.accuracy) }
                whiteCounts[c.classification.rawValue, default: 0] += 1
            } else {
                if c.countsTowardAverage { blackAcc.append(c.accuracy) }
                blackCounts[c.classification.rawValue, default: 0] += 1
            }
        }

        return GameReview(moves: reviews,
                          evals: evals.map { $0.eval },
                          whiteAccuracy: combine(whiteAcc),
                          blackAccuracy: combine(blackAcc),
                          whiteCounts: whiteCounts,
                          blackCounts: blackCounts,
                          opening: Openings.name(for: ucis),
                          engine: "\(StockfishEngine.versionName) (\(profile.title))",
                          depth: profile.analysisDepth,
                          generatedAt: Date())
    }

    // MARK: One position

    /// Asks the engine about a position (two lines, so the second-best move is known).
    /// Finished games are scored without the engine.
    static func evaluate(_ pos: Position, profile: EngineProfile) async throws -> PositionEval {
        switch pos.status() {
        case .checkmate:
            let cp = pos.turn == .white ? -10000 : 10000
            return PositionEval(eval: Eval(cp: cp, mate: nil), best: nil, second: nil)
        case .stalemate, .insufficientMaterial, .fiftyMoveRule:
            return PositionEval(eval: .draw, best: nil, second: nil)
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
                                    ?? "Stockfish không trả về đánh giá nào.")
            }
            let e = Eval.fromWhitePOV(line: top, turn: pos.turn)
            let s = r.lines.count > 1 ? Eval.fromWhitePOV(line: r.lines[1], turn: pos.turn) : nil
            return PositionEval(eval: e, best: r.bestMove ?? top.pv.first, second: s)
        }
    }

    /// Classifies one move with the Expected Points model:
    /// Forced > Book > Brilliant > Great > Miss > threshold table.
    /// `opponentLastLoss` is the expected points the opponent lost with their previous move
    /// (0 when it was forced or book).
    static func classify(position pos: Position,
                         move: Move,
                         next: Position,
                         before: PositionEval,
                         after: PositionEval,
                         isBook: Bool,
                         previous: (position: Position, move: Move)? = nil,
                         opponentLastLoss: Double,
                         rating: Int,
                         profile: EngineProfile) async throws -> ClassifiedMove {
        let mover = pos.turn
        // Below 2000 any net material loss counts as a sacrifice; above it must cost 2+ pawns.
        let sacrificeThreshold = rating < 2000 ? 1 : 2

        // Phase A/B: win probabilities from the mover's side and expected points lost.
        let pBefore = before.eval.winPercent(for: mover, rating: rating) / 100
        var pAfter = after.eval.winPercent(for: mover, rating: rating) / 100
        let playedBest = before.best == move.uci
        var epl = playedBest ? 0.0 : max(0, pBefore - pAfter)
        let legalCount = pos.legalMoves().count

        var cls: MoveClass
        if legalCount == 1 {
            cls = .forced
        } else if isBook {
            cls = .book
        } else {
            // Tier 3: Brilliant needs all of: EPL <= 0.02, a real sacrifice, not losing
            // afterwards (P >= 0.40) and not already winning (P < 0.90). The quick search may
            // not see the point of a sacrifice yet, so a promising one gets a deeper look.
            var brilliant = false
            if pBefore < 0.90, move.promotion == nil, atMost(epl, 0.08),
               sacrificeValue(pos: pos, move: move) >= sacrificeThreshold {
                var checkedEPL = epl
                var checkedAfter = pAfter
                if !atMost(epl, 0.02) || pAfter < 0.40, next.status() == .ongoing {
                    let deeper = await deeperWinPercent(after: next, for: mover,
                                                        rating: rating, profile: profile)
                    try Task.checkCancellation()
                    if let d = deeper {
                        checkedAfter = d / 100
                        checkedEPL = playedBest ? 0 : max(0, pBefore - checkedAfter)
                    }
                }
                if atMost(checkedEPL, 0.02), checkedAfter >= 0.40 {
                    brilliant = true
                    epl = checkedEPL
                    pAfter = checkedAfter
                }
            }

            // Tier 4: Great is any of: the only good move, turning the game around,
            // or (optionally) a swing away from a big advantage.
            var onlyGoodMove = false
            if let second = before.second {
                let pSecond = second.winPercent(for: mover, rating: rating) / 100
                onlyGoodMove = pBefore - pSecond > 0.10
            }
            // A plain recapture (taking back on the square where the opponent just took) is
            // the natural answer to an exchange, so it is only Great when it truly turns
            // the game around, not merely because not recapturing would lose a piece.
            var isRecapture = false
            if let prev = previous, move.to == prev.move.to, pos.board[move.to] != nil,
               prev.position.board[prev.move.to] != nil {
                isRecapture = true
            }
            let turnaround = pBefore < 0.50 && pAfter >= 0.70
            let great: Bool
            if isRecapture {
                great = turnaround
            } else {
                great = (onlyGoodMove && atMost(epl, 0.02))
                    || turnaround
                    || (greatIncludesLostAdvantage && pBefore >= 0.70 && pAfter < 0.50)
            }

            if brilliant {
                cls = .brilliant
            } else if great {
                cls = .great
            } else if opponentLastLoss >= 0.20 && epl >= 0.10 - 1e-6 {
                // Tier 5: the opponent just blundered and this move did not take advantage.
                cls = .miss
            } else if playedBest {
                // Phase D: best means the engine's own move; an equal-scoring alternative is excellent.
                cls = .best
            } else if atMost(epl, 0.02) {
                cls = .excellent
            } else if atMost(epl, 0.05) {
                cls = .good
            } else if atMost(epl, 0.10) {
                cls = .inaccuracy
            } else if atMost(epl, 0.20) {
                cls = .mistake
            } else {
                cls = .blunder
            }
        }

        // Phase E: accuracy. Forced and book moves are 100 but left out of the average.
        let acc: Double
        switch cls {
        case .forced, .book, .best, .brilliant, .great:
            acc = 100
        default:
            acc = accuracy(forEPL: epl)
        }

        var bestSAN: String? = nil
        if let b = before.best, let bm = pos.move(fromUCI: b) { bestSAN = pos.san(bm) }

        return ClassifiedMove(classification: cls,
                              epl: epl,
                              accuracy: acc,
                              bestUCI: before.best,
                              bestSAN: bestSAN,
                              countsTowardAverage: cls != .forced && cls != .book)
    }

    // MARK: Heuristics

    /// How much material (in pawns) the move gives up on purpose, minus what the move
    /// itself captures. Both kinds count: putting the moved piece where it can be taken
    /// (a sacrifice), and leaving a piece of the mover's en prise by playing something
    /// else, e.g. ignoring an attack on the queen (abandoning a piece). Only knights,
    /// bishops, rooks and queens count, and the opponent must have a legal capture. For
    /// the moved piece, danger it was already in on its old square is not counted again.
    private static func sacrificeValue(pos: Position, move: Move) -> Int {
        guard let moving = pos.board[move.from] else { return 0 }
        let mover = moving.side
        let opponent = mover.opposite
        let captured = pos.board[move.to]?.type.value ?? 0
        let next = pos.make(move)
        let replies = next.legalMoves()
        var risk = 0
        for sq in 0..<64 {
            guard let p = next.board[sq], p.side == mover, p.type != .king, p.type != .pawn else { continue }
            guard replies.contains(where: { $0.to == sq }) else { continue }
            let now = next.see(on: sq, by: opponent)
            if sq == move.to {
                // The piece that moved: only the extra danger it walked into.
                let already = pos.see(on: move.from, by: opponent)
                risk = max(risk, now - already)
            } else {
                // A piece that stayed behind and is left to be taken.
                risk = max(risk, now)
            }
        }
        return risk - captured
    }

    /// Second look at the position after a move with a deeper search. Returns the win
    /// probability of `mover`, or nil if the engine gave no answer.
    private static func deeperWinPercent(after pos: Position,
                                         for mover: Side,
                                         rating: Int,
                                         profile: EngineProfile) async -> Double? {
        let result = await StockfishEngine.shared.search(
            fen: pos.fen,
            depth: profile.analysisDepth + 6,
            movetimeMs: profile.analysisMaxMillis * 2,
            multiPV: 1,
            strength: .full,
            profile: profile)
        guard let top = result?.lines.first else { return nil }
        return Eval.fromWhitePOV(line: top, turn: pos.turn).winPercent(for: mover, rating: rating)
    }
}
