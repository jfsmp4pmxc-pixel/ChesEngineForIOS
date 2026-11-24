import Foundation

/// A compact opening book used to label "Book" moves and to name the opening.
/// Lines are written in SAN and converted to UCI on first use. A line that fails to
/// parse is simply truncated at the bad move.
enum Openings {
    private struct Entry {
        let name: String
        let ucis: [String]
    }

    private static let source: [(String, String)] = [
        ("King's Pawn Game", "e4"),
        ("Queen's Pawn Game", "d4"),
        ("English Opening", "c4"),
        ("Réti Opening", "Nf3"),
        ("Bird Opening", "f4"),
        ("King's Pawn Game: Open Game", "e4 e5"),
        ("Queen's Pawn Game: Closed", "d4 d5"),
        ("Indian Defense", "d4 Nf6"),
        ("Sicilian Defense", "e4 c5"),
        ("French Defense", "e4 e6 d4 d5"),
        ("Caro-Kann Defense", "e4 c6 d4 d5"),
        ("Scandinavian Defense", "e4 d5"),
        ("Pirc Defense", "e4 d6 d4 Nf6 Nc3 g6"),
        ("Alekhine's Defense", "e4 Nf6"),
        ("Italian Game", "e4 e5 Nf3 Nc6 Bc4"),
        ("Italian Game: Giuoco Piano", "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O"),
        ("Two Knights Defense", "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Na5 Bb5+ c6 dxc6 bxc6 Be2"),
        ("Evans Gambit", "e4 e5 Nf3 Nc6 Bc4 Bc5 b4 Bxb4 c3 Ba5 d4 exd4 O-O Nge7 Ng5 O-O"),
        ("Ruy Lopez", "e4 e5 Nf3 Nc6 Bb5"),
        ("Ruy Lopez: Morphy Defense", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3"),
        ("Ruy Lopez: Berlin Defense", "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6 dxe5 Nf5 Qxd8+ Kxd8"),
        ("Scotch Game", "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7 Qe2 Nd5 c4 Ba6"),
        ("Petrov's Defense", "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Nc6 O-O Be7 c4 Nb4"),
        ("Philidor Defense", "e4 e5 Nf3 d6 d4 Nf6 Nc3 Nbd7 Bc4 Be7 O-O O-O Re1 c6 a4"),
        ("Four Knights Game", "e4 e5 Nf3 Nc6 Nc3 Nf6 Bb5 Bb4 O-O O-O d3 d6 Bg5 Bxc3 bxc3 Qe7 Re1 Nd8 d4 Ne6"),
        ("Vienna Game", "e4 e5 Nc3 Nf6 f4 d5 fxe5 Nxe4 Nf3 Be7 d4 O-O Bd3 f5"),
        ("King's Gambit", "e4 e5 f4 exf4 Nf3 g5 h4 g4 Ne5 Nf6 Bc4 d5 exd5 Bd6"),
        ("Sicilian Defense: Najdorf", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O"),
        ("Sicilian Defense: Dragon", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6"),
        ("Sicilian Defense: Sveshnikov", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6 Bg5 a6 Na3 b5 Nd5"),
        ("Sicilian Defense: Taimanov", "e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6 Nc3 Qc7 Be3 a6 Qd2 Nf6 O-O-O Bb4"),
        ("Sicilian Defense: Alapin", "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4 Nf3 Nc6 cxd4 d6 Bc4 Nb6 Bb3 dxe5 Nxe5"),
        ("Sicilian Defense: Closed", "e4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 d3 d6 Be3"),
        ("French Defense: Classical", "e4 e6 d4 d5 Nc3 Nf6 Bg5 Be7 e5 Nfd7 Bxe7 Qxe7 f4 O-O Nf3 c5"),
        ("French Defense: Winawer", "e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Qg4 Qc7 Qxg7 Rg8 Qxh7 cxd4 Ne2 Nbc6"),
        ("French Defense: Advance", "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6 a3 Nh6 b4 cxd4 cxd4 Nf5"),
        ("French Defense: Tarrasch", "e4 e6 d4 d5 Nd2 Nf6 e5 Nfd7 Bd3 c5 c3 Nc6 Ne2 cxd4 cxd4 f6"),
        ("Caro-Kann Defense: Classical", "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6 Nf3 Nd7 h5 Bh7 Bd3 Bxd3 Qxd3 e6"),
        ("Caro-Kann Defense: Advance", "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5 Be3 Nd7 O-O Ne7 c4 Nc6"),
        ("Caro-Kann Defense: Panov Attack", "e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Bb4 cxd5 Nxd5 Bd2 Nc6 Bd3"),
        ("Pirc Defense: Austrian Attack", "e4 d6 d4 Nf6 Nc3 g6 f4 Bg7 Nf3 O-O Bd3 Na6 O-O c5"),
        ("Scandinavian Defense: Main Line", "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6 Bc4 Bf5 Bd2 e6 Qe2 Bb4"),
        ("Alekhine's Defense: Four Pawns", "e4 Nf6 e5 Nd5 d4 d6 Nf3 Bg4 Be2 e6 O-O Be7 c4 Nb6 Nc3 O-O"),
        ("Queen's Gambit", "d4 d5 c4"),
        ("Queen's Gambit Declined", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6 cxd5 Nxd5 Bxe7 Qxe7"),
        ("Queen's Gambit Accepted", "d4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6 Bb3 cxd4 exd4 Nc6"),
        ("Slav Defense", "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O O-O Qe2 Nbd7"),
        ("Semi-Slav Defense", "d4 d5 c4 c6 Nf3 Nf6 Nc3 e6 e3 Nbd7 Bd3 dxc4 Bxc4 b5 Bd3 a6 e4 c5"),
        ("Nimzo-Indian Defense", "d4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O Nc6 a3 Bxc3 bxc3 dxc4 Bxc4 Qc7"),
        ("Queen's Indian Defense", "d4 Nf6 c4 e6 Nf3 b6 g3 Ba6 b3 Bb4+ Bd2 Be7 Bg2 c6 Bc3 d5 Ne5 Nfd7"),
        ("King's Indian Defense", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7"),
        ("Grünfeld Defense", "d4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Nf3 c5 Rb1 O-O Be2 Nc6"),
        ("Catalan Opening", "d4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3 O-O O-O dxc4 Qc2 a6 a4 Bd7"),
        ("London System", "d4 d5 Bf4 Nf6 e3 e6 Nf3 Bd6 Bg3 O-O Nbd2 c5 c3 Nc6 Bd3"),
        ("Dutch Defense", "d4 f5 g3 Nf6 Bg2 e6 Nf3 Be7 O-O O-O c4 d6 Nc3 Qe8"),
        ("English Opening: Reversed Sicilian", "c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5 Bg2 Nb6 O-O Be7 d3 O-O"),
        ("English Opening: Symmetrical", "c4 c5 Nf3 Nf6 Nc3 Nc6 g3 g6 Bg2 Bg7 O-O O-O d4 cxd4 Nxd4"),
        ("Réti Opening: King's Indian Attack", "Nf3 d5 c4 e6 g3 Nf6 Bg2 Be7 O-O O-O b3 c5 Bb2 Nc6")
    ]

    private static let entries: [Entry] = {
        return source.map { name, san in
            var pos = Position.start
            var ucis: [String] = []
            for token in san.split(separator: " ") {
                guard let m = pos.move(fromSAN: String(token)) else { break }
                ucis.append(m.uci)
                pos = pos.make(m)
            }
            return Entry(name: name, ucis: ucis)
        }
    }()

    private static func commonPrefix(_ a: [String], _ b: [String]) -> Int {
        var n = 0
        while n < a.count && n < b.count && a[n] == b[n] { n += 1 }
        return n
    }

    /// Number of leading plies of `ucis` that are still inside the book.
    static func bookPlies(for ucis: [String]) -> Int {
        var best = 0
        for e in entries {
            best = max(best, commonPrefix(e.ucis, ucis))
        }
        return best
    }

    /// Most specific opening name for the moves played so far (nil if none matches).
    static func name(for ucis: [String]) -> String? {
        var bestLen = 0
        var bestEntry: Entry? = nil
        for e in entries {
            let c = commonPrefix(e.ucis, ucis)
            guard c > 0 else { continue }
            if c > bestLen || (c == bestLen && e.ucis.count < (bestEntry?.ucis.count ?? Int.max)) {
                bestLen = c
                bestEntry = e
            }
        }
        return bestEntry?.name
    }
}
