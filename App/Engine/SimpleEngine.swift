import Foundation

/// A small fallback player for positions Stockfish cannot take (more than 32 pieces).
/// It looks one move ahead: grabs material, mates when it can, and avoids putting the
/// moved piece where it is simply lost. Weak on purpose; it only keeps the game going.
enum SimpleEngine {
    static func bestMove(_ pos: Position) -> Move? {
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }
        let me = pos.turn
        var best: Move? = nil
        var bestScore = -Double.infinity

        for m in moves {
            let next = pos.make(m)
            var score: Double
            switch next.status() {
            case .checkmate:
                return m
            case .stalemate, .insufficientMaterial, .fiftyMoveRule:
                score = 0
            case .ongoing:
                score = Double(material(next, for: me))
                score -= Double(max(0, next.see(on: m.to, by: me.opposite)))
                if next.inCheck { score += 0.3 }
            }
            score += Double.random(in: 0..<0.25)
            if score > bestScore {
                bestScore = score
                best = m
            }
        }
        return best ?? moves.randomElement()
    }

    private static func material(_ pos: Position, for side: Side) -> Int {
        var total = 0
        for sq in 0..<64 {
            guard let p = pos.board[sq] else { continue }
            total += p.side == side ? p.type.value : -p.type.value
        }
        return total
    }
}
