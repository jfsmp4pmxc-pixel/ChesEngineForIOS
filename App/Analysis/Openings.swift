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
        ("Réti Opening: King's Indian Attack", "Nf3 d5 c4 e6 g3 Nf6 Bg2 Be7 O-O O-O b3 c5 Bb2 Nc6"),
        ("King's Pawn Game: Mieses Opening", "e4 e5 d3"),
        ("King's Pawn Game: Center Game", "e4 e5 d4 exd4 Qxd4 Nc6 Qe3 Nf6"),
        ("King's Pawn Game: Danish Gambit", "e4 e5 d4 exd4 c3 dxc3 Bc4 cxb2 Bxb2 d5 Bxd5 Nf6"),
        ("King's Pawn Game: Bishop's Opening", "e4 e5 Bc4 Nf6 d3 c6 Nf3 d5 Bb3 Bd6"),
        ("King's Pawn Game: Ponziani Opening", "e4 e5 Nf3 Nc6 c3 Nf6 d4 Nxe4 d5 Ne7 Nxe5 Ng6"),
        ("King's Pawn Game: Elephant Gambit", "e4 e5 Nf3 d5 exd5 e4 Qe2 Qxd5 Nc3 Qe6"),
        ("King's Pawn Game: Latvian Gambit", "e4 e5 Nf3 f5 Nxe5 Qf6 d4 d6 Nc4 fxe4 Nc3 Qg6"),
        ("King's Pawn Game: Damiano Defense", "e4 e5 Nf3 f6 Nxe5 fxe5 Qh5+ Ke7 Qxe5+ Kf7 Bc4+ d5"),
        ("King's Pawn Game: Philidor Defense, Hanham Variation", "e4 e5 Nf3 d6 d4 Nd7 Bc4 c6 O-O Be7"),
        ("King's Pawn Game: Petrov's Defense, Classical", "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 Nc3 Nxc3 dxc3 Be7 Be3 Nc6 Qd2 Be6"),
        ("King's Pawn Game: Petrov's Defense, Three Knights", "e4 e5 Nf3 Nf6 Nc3 Nc6 Bb5 Bb4 O-O O-O d3 Bxc3 bxc3 d6 Bg5 Qe7"),
        ("King's Pawn Game: Scotch Gambit", "e4 e5 Nf3 Nc6 d4 exd4 Bc4 Nf6 e5 d5 Bb5 Ne4 Nxd4 Bd7"),
        ("King's Pawn Game: Scotch Game, Classical", "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Bc5 Nxc6 Qf6 Qd2 dxc6 Nc3 Ne7"),
        ("King's Pawn Game: Scotch Game, Mieses Variation", "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7 Qe2 Nd5 c4 Ba6 b3 g5"),
        ("King's Pawn Game: Scotch Game, Schmidt Variation", "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7 Qe2 Nd5 c4 Nb6 Nc3 Qe6"),
        ("King's Pawn Game: Scotch Four Knights", "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nc3 Bb4 Nxc6 bxc6 Bd3 d5 exd5 cxd5 O-O O-O"),
        ("Italian Game: Giuoco Pianissimo", "e4 e5 Nf3 Nc6 Bc4 Bc5 d3 Nf6 c3 d6 Nbd2 a6 Bb3 Ba7"),
        ("Italian Game: Giuoco Piano, Main Line", "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 bxc3 d5"),
        ("Italian Game: Giuoco Piano, Greco Attack", "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Bd2 Bxd2+ Nbxd2 d5 exd5 Nxd5 Qb3 Nce7"),
        ("Italian Game: Hungarian Defense", "e4 e5 Nf3 Nc6 Bc4 Be7 d4 exd4 Nxd4 Nf6 Nc3 O-O"),
        ("Italian Game: Evans Gambit Declined", "e4 e5 Nf3 Nc6 Bc4 Bc5 b4 Bb6 a4 a6 Nc3 Nf6 d3 d6"),
        ("Italian Game: Two Knights, Fried Liver Attack", "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Nxd5 Nxf7 Kxf7 Qf3+ Ke6 Nc3 Nb4"),
        ("Italian Game: Two Knights, Traxler Counterattack", "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 Bc5 Nxf7 Bxf2+ Kxf2 Nxe4+ Kg1 Qh4 Nxh8 d5"),
        ("Italian Game: Two Knights, Modern Bishop's Opening", "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O Re1 d6 c3 Na5 Bb3 Nxb3"),
        ("Ruy Lopez: Exchange Variation", "e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6 O-O f6 d4 exd4 Nxd4 c5 Nb3 Qxd1 Rxd1 Bg4"),
        ("Ruy Lopez: Closed, Chigorin Defense", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Na5 Bc2 c5 d4 Qc7"),
        ("Ruy Lopez: Closed, Breyer Defense", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7"),
        ("Ruy Lopez: Closed, Marshall Attack", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 O-O c3 d5 exd5 Nxd5 Nxe5 Nxe5 Rxe5 c6"),
        ("Ruy Lopez: Open Variation", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Nxe4 d4 b5 Bb3 d5 dxe5 Be6 c3 Be7 Nbd2 O-O"),
        ("Ruy Lopez: Schliemann Defense", "e4 e5 Nf3 Nc6 Bb5 f5 Nc3 fxe4 Nxe4 d5 Nxe5 dxe4 Nxc6 Qg5"),
        ("Ruy Lopez: Classical Defense", "e4 e5 Nf3 Nc6 Bb5 Bc5 c3 Nf6 O-O O-O d4 Bb6 Bxc6 dxc6 dxe5 Nxe4"),
        ("Ruy Lopez: Steinitz Defense", "e4 e5 Nf3 Nc6 Bb5 d6 d4 Bd7 Nc3 Nf6 O-O Be7 Re1 exd4 Nxd4 O-O"),
        ("Ruy Lopez: Arkhangelsk Defense", "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O b5 Bb3 Bb7 Re1 Bc5 c3 d6 d4 Bb6"),
        ("Vienna Game: Falkbeer Variation", "e4 e5 Nc3 Nc6 Bc4 Nf6 d3 Na5 Nge2 Nxc4 dxc4 d6"),
        ("Vienna Game: Frankenstein-Dracula Variation", "e4 e5 Nc3 Nf6 Bc4 Nxe4 Qh5 Nd6 Bb3 Nc6 Nb5 g6 Qf3 f5"),
        ("King's Gambit Accepted: Kieseritzky Gambit", "e4 e5 f4 exf4 Nf3 g5 h4 g4 Ne5 Nf6 Bc4 d5 exd5 Bd6 d4 Nh5"),
        ("King's Gambit Accepted: Bishop's Gambit", "e4 e5 f4 exf4 Bc4 Nf6 Nc3 c6 Nf3 d5 exd5 cxd5 Bb3 Nc6"),
        ("King's Gambit Accepted: Fischer Defense", "e4 e5 f4 exf4 Nf3 g5 Bc4 g4 O-O gxf3 Qxf3 Qf6 e5 Qxe5 Bxf7+ Kxf7 d4 Qxd4+"),
        ("King's Gambit Declined: Falkbeer Counter Gambit", "e4 e5 f4 d5 exd5 e4 d3 Nf6 dxe4 Nxe4 Nf3 Bc5 Qe2 Qe7 Bd2 Nxd2"),
        ("King's Gambit Declined: Classical", "e4 e5 f4 Bc5 Nf3 d6 c3 Nf6 Bc4 Nc6 d3 Bg4"),
        ("Sicilian Defense: Najdorf, English Attack", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O g4"),
        ("Sicilian Defense: Najdorf, Poisoned Pawn", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6 Qd2 Qxb2 Rb1 Qa3"),
        ("Sicilian Defense: Najdorf, Scheveningen", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 e6 O-O Be7 f4 O-O Be3 Nc6"),
        ("Sicilian Defense: Najdorf, Bg5", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Be7 Qf3 Qc7 O-O-O Nbd7"),
        ("Sicilian Defense: Najdorf, Adams Attack", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 h3 e5 Nde2 h5 g3 Be6"),
        ("Sicilian Defense: Dragon, Yugoslav Attack", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6 Bc4 Bd7 O-O-O Rc8 Bb3 Ne5"),
        ("Sicilian Defense: Dragon, Classical", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be2 Bg7 O-O O-O Nb3 Be6 f4 Qc8"),
        ("Sicilian Defense: Accelerated Dragon", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 Nc3 Bg7 Be3 Nf6 Bc4 O-O Bb3 d6"),
        ("Sicilian Defense: Accelerated Dragon, Maróczy Bind", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Bg7 Be3 Nf6 Nc3 Ng4 Qxg4 Nxd4"),
        ("Sicilian Defense: Scheveningen", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6 Be2 Be7 O-O O-O f4 Nc6 Be3 a6"),
        ("Sicilian Defense: Classical", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Bg5 e6 Qd2 a6 O-O-O Bd7 f4 Be7"),
        ("Sicilian Defense: Richter-Rauzer", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Bg5 e6 Qd2 a6 O-O-O Bd7 f4 b5"),
        ("Sicilian Defense: Kan", "e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Nc6 Nxc6 bxc6 O-O d5 c4 Nf6"),
        ("Sicilian Defense: Paulsen", "e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Be2 Nc6 Be3 Qc7 O-O Nf6 Nb3 b5"),
        ("Sicilian Defense: Four Knights", "e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Ndb5 Bb4 a3 Bxc3+ Nxc3 d5 exd5 exd5"),
        ("Sicilian Defense: Sveshnikov, Chelyabinsk", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6 Bg5 a6 Na3 b5 Bxf6 gxf6 Nd5 f5"),
        ("Sicilian Defense: Kalashnikov", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 e5 Nb5 d6 N1c3 a6 Na3 Be6 Nc4 Nf6"),
        ("Sicilian Defense: Alapin, Smith-Morra Gambit", "e4 c5 d4 cxd4 c3 dxc3 Nxc3 Nc6 Nf3 d6 Bc4 e6 O-O Nf6 Qe2 Be7"),
        ("Sicilian Defense: Grand Prix Attack", "e4 c5 Nc3 Nc6 f4 g6 Nf3 Bg7 Bc4 e6 f5 Nge7"),
        ("Sicilian Defense: Bowdler Attack", "e4 c5 Nf3 e6 Bc4 Nc6 O-O Nf6 d3 d5 exd5 exd5 Bb3 Be7"),
        ("Sicilian Defense: Smith-Morra Gambit Accepted", "e4 c5 d4 cxd4 c3 dxc3 Nxc3 e6 Nf3 Nc6 Bc4 Qc7 O-O Nf6 Qe2 Bb4"),
        ("Sicilian Defense: Nimzowitsch Variation", "e4 c5 Nf3 Nf6 e5 Nd5 Nc3 e6 Nxd5 exd5 d4 Nc6 dxc5 Bxc5 Qxd5 Qb6"),
        ("Sicilian Defense: O'Kelly Variation", "e4 c5 Nf3 a6 c3 d5 exd5 Qxd5 d4 Nf6 Be2 e6"),
        ("Sicilian Defense: Hyperaccelerated Dragon", "e4 c5 Nf3 g6 d4 cxd4 Nxd4 Bg7 Nc3 Nc6 Be3 Nf6 Bc4 O-O"),
        ("French Defense: Exchange", "e4 e6 d4 d5 exd5 exd5 Nf3 Nf6 Bd3 Bd6 O-O O-O Bg5 Bg4"),
        ("French Defense: Rubinstein", "e4 e6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Nf3 Ngf6 Nxf6+ Nxf6 Bd3 c5 dxc5 Bxc5"),
        ("French Defense: McCutcheon", "e4 e6 d4 d5 Nc3 Nf6 Bg5 Bb4 e5 h6 Bd2 Bxc3 bxc3 Ne4 Qg4 Kf8"),
        ("French Defense: Burn Variation", "e4 e6 d4 d5 Nc3 Nf6 Bg5 dxe4 Nxe4 Be7 Bxf6 gxf6 Nf3 f5 Ng3 Nc6"),
        ("French Defense: Winawer, Poisoned Pawn", "e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Qg4 Qc7 Qxg7 Rg8 Qxh7 cxd4 Kd1 Bd7"),
        ("French Defense: King's Indian Attack", "e4 e6 d3 d5 Nd2 Nf6 Ngf3 c5 g3 Nc6 Bg2 Be7 O-O O-O"),
        ("French Defense: Tarrasch, Closed", "e4 e6 d4 d5 Nd2 c5 exd5 exd5 Ngf3 Nc6 Bb5 Bd6 dxc5 Bxc5 O-O Nge7"),
        ("French Defense: Tarrasch, Open System", "e4 e6 d4 d5 Nd2 Nf6 e5 Nfd7 Bd3 c5 c3 Nc6 Ne2 cxd4 cxd4 f6 exf6 Nxf6 Nf3 Bd6"),
        ("Caro-Kann Defense: Exchange", "e4 c6 d4 d5 exd5 cxd5 Bd3 Nc6 c3 Nf6 Bf4 Bg4 Qb3 Qd7"),
        ("Caro-Kann Defense: Two Knights", "e4 c6 Nc3 d5 Nf3 Bg4 h3 Bxf3 Qxf3 e6 d3 Nf6"),
        ("Caro-Kann Defense: Fantasy Variation", "e4 c6 d4 d5 f3 dxe4 fxe4 e5 Nf3 exd4 Bc4 Nf6 Qxd4 Qxd4"),
        ("Caro-Kann Defense: Karpov Variation", "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Ng5 Ngf6 Bd3 e6 N1f3 Bd6 Qe2 h6"),
        ("Caro-Kann Defense: Bronstein-Larsen", "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Nf6 Nxf6+ gxf6 Nf3 Bg4 h3 Bxf3 Qxf3 e6"),
        ("Caro-Kann Defense: Gurgenidze", "e4 c6 d4 d5 Nc3 g6 Nf3 Bg7 h3 Nf6 Bd3 O-O O-O dxe4 Nxe4 Nxe4 Bxe4 Nd7"),
        ("Caro-Kann Defense: Short Variation", "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 Nd7 O-O Ne7 Nbd2 h6 Nh4 Bg6"),
        ("Scandinavian Defense: Modern", "e4 d5 exd5 Nf6 d4 Nxd5 Nf3 g6 Be2 Bg7 O-O O-O c4 Nb6"),
        ("Scandinavian Defense: Icelandic-Palme Gambit", "e4 d5 exd5 Nf6 c4 e6 dxe6 Bxe6 d4 Bb4+ Bd2 Qe7"),
        ("Scandinavian Defense: Portuguese Gambit", "e4 d5 exd5 Nf6 d4 Bg4 Nf3 Bxf3 gxf3 Nxd5 c4 Nb6"),
        ("Scandinavian Defense: Classical", "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 c6 Nf3 Nf6 Bc4 Bf5 Bd2 e6 Nd5"),
        ("Pirc Defense: Classical", "e4 d6 d4 Nf6 Nc3 g6 Nf3 Bg7 Be2 O-O O-O Bg4 Be3 Nc6 Qd3 e5"),
        ("Pirc Defense: 150 Attack", "e4 d6 d4 Nf6 Nc3 g6 Be3 Bg7 Qd2 c6 f3 b5 Nge2 Nbd7"),
        ("Pirc Defense: Byrne Variation", "e4 d6 d4 Nf6 Nc3 g6 Bg5 Bg7 Qd2 h6 Bh4 c6 O-O-O Nbd7 f3 b5"),
        ("Modern Defense", "e4 g6 d4 Bg7 Nc3 d6 Nf3 a6 Be2 b5 O-O Nd7"),
        ("Alekhine's Defense: Modern Variation", "e4 Nf6 e5 Nd5 d4 d6 Nf3 Bg4 Be2 e6 O-O Be7 h3 Bh5 c4 Nb6"),
        ("Alekhine's Defense: Exchange", "e4 Nf6 e5 Nd5 d4 d6 c4 Nb6 exd6 exd6 Nc3 Be7 Bd3 Nc6"),
        ("Alekhine's Defense: Scandinavian Variation", "e4 Nf6 Nc3 d5 e5 Ne4 Nxe4 dxe4 d4 e6 Ne2 Nc6 Be3 Bb4+ c3 Bd6"),
        ("Nimzowitsch Defense", "e4 Nc6 Nf3 d6 d4 Nf6 Nc3 Bg4 Be3 e6 Be2 Be7 O-O O-O"),
        ("St. George Defense", "e4 a6 d4 b5 Nf3 Bb7 Bd3 Nf6 Qe2 e6 a4 c5"),
        ("Owen Defense", "e4 b6 d4 Bb7 Bd3 e6 Nf3 Nf6 O-O Be7 Nbd2 c5 c3 Nc6"),
        ("Queen's Pawn Game: Veresov Attack", "d4 d5 Nc3 Nf6 Bg5 Nbd7 Nf3 e6 e3 Be7 Bd3 O-O Qe2 c5"),
        ("Queen's Pawn Game: Torre Attack", "d4 Nf6 Nf3 e6 Bg5 c5 e3 Be7 Nbd2 b6 c3 Bb7 Bd3 O-O"),
        ("Queen's Pawn Game: Trompowsky Attack", "d4 Nf6 Bg5 Ne4 Bf4 c5 f3 Qa5+ c3 Nf6 d5 Qb6 Qd2 e6"),
        ("Queen's Pawn Game: Colle System", "d4 d5 Nf3 Nf6 e3 e6 Bd3 c5 b3 Nc6 O-O Bd6 Bb2 O-O Nbd2 b6"),
        ("Queen's Pawn Game: Zukertort Variation", "d4 d5 Nf3 Nf6 Bf4 e6 e3 c5 c3 Nc6 Nbd2 Bd6 Bg3 O-O"),
        ("Queen's Pawn Game: Chigorin Defense", "d4 d5 c4 Nc6 Nc3 dxc4 d5 Ne5 e4 Ng6 Bxc4 e6"),
        ("Queen's Pawn Game: Jobava London System", "d4 d5 Nc3 Nf6 Bf4 c6 Nb5 Na6 Nf3 Bf5 e3 e6 Be2 Be7"),
        ("Queen's Pawn Game: Stonewall Attack", "d4 d5 e3 Nf6 Bd3 c5 c3 Nc6 f4 e6 Nf3 Bd6 O-O O-O"),
        ("Queen's Gambit Declined: Orthodox Defense", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7 Rc1 c6 Bd3 dxc4 Bxc4 Nd5"),
        ("Queen's Gambit Declined: Tartakower Defense", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6 Bd3 Bb7 O-O Nbd7"),
        ("Queen's Gambit Declined: Exchange Variation", "d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 c6 Bd3 Nbd7 Qc2 O-O Nge2 Re8"),
        ("Queen's Gambit Declined: Ragozin Defense", "d4 d5 c4 e6 Nc3 Nf6 Nf3 Bb4 Bg5 h6 Bh4 dxc4 e4 g5 Bg3 b5"),
        ("Queen's Gambit Declined: Vienna Variation", "d4 d5 c4 e6 Nc3 Nf6 Nf3 Bb4 Bg5 dxc4 e4 b5 a4 c6 Bxc4 Bb7"),
        ("Queen's Gambit Declined: Albin Countergambit", "d4 d5 c4 e5 dxe5 d4 Nf3 Nc6 g3 Be6 Nbd2 Qd7 Bg2 O-O-O"),
        ("Queen's Gambit Declined: Cambridge Springs", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Nbd7 e3 c6 Nf3 Qa5 Nd2 Bb4 Qc2 O-O Bd3 dxc4"),
        ("Queen's Gambit Accepted: Central Variation", "d4 d5 c4 dxc4 e4 e5 Nf3 exd4 Bxc4 Bb4+ Nbd2 Nc6"),
        ("Queen's Gambit Accepted: Classical", "d4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6 a4 Nc6 Qe2 cxd4 Rd1 Be7"),
        ("Slav Defense: Exchange", "d4 d5 c4 c6 cxd5 cxd5 Nc3 Nf6 Nf3 Nc6 Bf4 Bf5 e3 e6 Bb5 Bb4"),
        ("Slav Defense: Czech Variation", "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O Nbd7 Qe2 Bg6"),
        ("Slav Defense: Schlechter Variation", "d4 d5 c4 c6 Nf3 Nf6 e3 g6 Nc3 Bg7 Be2 O-O O-O Bg4 b3 Nbd7"),
        ("Slav Defense: Chebanenko Variation", "d4 d5 c4 c6 Nf3 Nf6 Nc3 a6 e3 b5 c5 g6 Be2 Bg7 O-O O-O b4 Nbd7"),
        ("Semi-Slav Defense: Meran Variation", "d4 d5 c4 c6 Nf3 Nf6 Nc3 e6 e3 Nbd7 Bd3 dxc4 Bxc4 b5 Bd3 Bb7 O-O a6 e4 c5 d5 Qc7"),
        ("Semi-Slav Defense: Botvinnik Variation", "d4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 dxc4 e4 b5 e5 h6 Bh4 g5 Nxg5 hxg5 Bxg5 Nbd7"),
        ("Semi-Slav Defense: Anti-Meran Gambit", "d4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 h6 Bxf6 Qxf6 e3 Nd7 Bd3 dxc4 Bxc4 g6"),
        ("Semi-Slav Defense: Moscow Variation", "d4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 h6 Bh4 dxc4 e4 g5 Bg3 b5 Be2 Bb7"),
        ("Nimzo-Indian Defense: Classical", "d4 Nf6 c4 e6 Nc3 Bb4 Qc2 O-O a3 Bxc3+ Qxc3 b6 Bg5 Bb7 e3 d6 f3 Nbd7"),
        ("Nimzo-Indian Defense: Rubinstein System", "d4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O Nc6 a3 Bxc3 bxc3 dxc4 Bxc4 Qc7"),
        ("Nimzo-Indian Defense: Sämisch Variation", "d4 Nf6 c4 e6 Nc3 Bb4 a3 Bxc3+ bxc3 c5 f3 d5 cxd5 Nxd5 dxc5 f5"),
        ("Nimzo-Indian Defense: Leningrad Variation", "d4 Nf6 c4 e6 Nc3 Bb4 Bg5 h6 Bh4 c5 d5 d6 e3 exd5 cxd5 Bxc3+ bxc3 Qe7"),
        ("Nimzo-Indian Defense: Kasparov Variation", "d4 Nf6 c4 e6 Nc3 Bb4 Nf3 c5 g3 Nc6 Bg2 Bxc3+ bxc3 d6 O-O O-O"),
        ("Nimzo-Indian Defense: Hübner Variation", "d4 Nf6 c4 e6 Nc3 Bb4 e3 c5 Bd3 Nc6 Nf3 Bxc3+ bxc3 d6 e4 e5"),
        ("Queen's Indian Defense: Fianchetto", "d4 Nf6 c4 e6 Nf3 b6 g3 Bb7 Bg2 Be7 O-O O-O Nc3 Ne4 Qc2 Nxc3 Qxc3 c5"),
        ("Queen's Indian Defense: Petrosian Variation", "d4 Nf6 c4 e6 Nf3 b6 a3 Bb7 Nc3 d5 cxd5 Nxd5 Qc2 Nxc3 Qxc3 Be7"),
        ("Bogo-Indian Defense", "d4 Nf6 c4 e6 Nf3 Bb4+ Bd2 Qe7 g3 Nc6 Nc3 Bxc3 Bxc3 Ne4 Rc1 O-O"),
        ("Catalan Opening: Open Defense", "d4 Nf6 c4 e6 g3 d5 Bg2 dxc4 Nf3 Be7 O-O O-O Qc2 a6 Qxc4 b5 Qc2 Bb7"),
        ("Catalan Opening: Closed", "d4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3 O-O O-O c6 Qc2 Nbd7 Nbd2 b6 b3 Bb7"),
        ("King's Indian Defense: Classical", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 Be3 f5"),
        ("King's Indian Defense: Sämisch Variation", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 Nh5 Qd2 f5 O-O-O Na6"),
        ("King's Indian Defense: Four Pawns Attack", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5 d5 e6 Be2 exd5 cxd5 Bg4"),
        ("King's Indian Defense: Fianchetto Variation", "d4 Nf6 c4 g6 g3 Bg7 Bg2 O-O Nc3 d6 Nf3 Nbd7 O-O e5 e4 c6 h3 Qb6"),
        ("King's Indian Defense: Averbakh Variation", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5 c5 d5 e6 Qd2 exd5 exd5 Re8"),
        ("King's Indian Defense: Petrosian Variation", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 d5 a5 Bg5 h6 Bh4 Na6"),
        ("Grünfeld Defense: Exchange Variation", "d4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Nf3 c5 Be3 Qa5 Qd2 Bg4 Rc1 Bxf3"),
        ("Grünfeld Defense: Russian System", "d4 Nf6 c4 g6 Nc3 d5 Nf3 Bg7 Qb3 dxc4 Qxc4 O-O e4 Bg4 Be3 Nfd7 Qb3 Nb6"),
        ("Grünfeld Defense: Fianchetto Variation", "d4 Nf6 c4 g6 g3 Bg7 Bg2 d5 cxd5 Nxd5 e4 Nb6 Ne2 O-O O-O Nc6"),
        ("Benoni Defense: Modern", "d4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 Nf3 Bg7 Be2 O-O O-O Re8"),
        ("Benoni Defense: Czech", "d4 Nf6 c4 c5 d5 e5 Nc3 d6 e4 Be7 Nf3 Nbd7 Be2 O-O O-O Ne8"),
        ("Benoni Defense: Taimanov Attack", "d4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 f4 Bg7 Bb5+ Nfd7 a4 O-O"),
        ("Benko Gambit", "d4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6 Bxa6 Nc3 d6 e4 Bxf1 Kxf1 g6 g3 Bg7 Kg2 O-O"),
        ("Old Indian Defense", "d4 Nf6 c4 d6 Nc3 Nbd7 e4 e5 Nf3 Be7 Be2 O-O O-O c6"),
        ("Budapest Gambit", "d4 Nf6 c4 e5 dxe5 Ng4 Bf4 Nc6 Nf3 Bb4+ Nbd2 Qe7 e3 Ngxe5"),
        ("Dutch Defense: Leningrad", "d4 f5 g3 Nf6 Bg2 g6 Nf3 Bg7 O-O O-O c4 d6 Nc3 Qe8"),
        ("Dutch Defense: Stonewall", "d4 f5 g3 Nf6 Bg2 e6 Nf3 d5 O-O Bd6 c4 c6 b3 Qe7"),
        ("Dutch Defense: Classical", "d4 f5 c4 Nf6 g3 e6 Bg2 Be7 Nf3 O-O O-O d6 Nc3 Qe8 Qc2 Qh5"),
        ("London System: Jobava Attack", "d4 d5 Bf4 Nf6 e3 c5 c3 Nc6 Nd2 e6 Ngf3 Bd6 Bg3 O-O Bd3 b6"),
        ("London System: Accelerated", "d4 Nf6 Bf4 g6 e3 Bg7 Nf3 O-O h3 d6 Be2 Nbd7 O-O c5"),
        ("English Opening: Four Knights", "c4 e5 Nc3 Nf6 Nf3 Nc6 e3 Bb4 Qc2 Bxc3 Qxc3 Qe7 Be2 d6 O-O O-O"),
        ("English Opening: Botvinnik System", "c4 e5 Nc3 Nc6 g3 g6 Bg2 Bg7 e4 d6 Nge2 Nge7 O-O O-O d3 Be6"),
        ("English Opening: Anglo-Indian Defense", "c4 Nf6 Nc3 e6 Nf3 Bb4 Qc2 O-O a3 Bxc3 Qxc3 b6 e4 Bb7 Bd3 d6"),
        ("English Opening: Symmetrical, Hedgehog", "c4 c5 Nf3 Nf6 Nc3 e6 g3 b6 Bg2 Bb7 O-O Be7 d4 cxd4 Qxd4 d6 Rd1 a6"),
        ("English Opening: Anglo-Dutch", "c4 f5 Nc3 Nf6 g3 g6 Bg2 Bg7 d3 O-O e4 d6 Nge2 c6"),
        ("English Opening: Agincourt Defense", "c4 e6 Nc3 d5 d4 Nf6 Nf3 Be7 Bg5 O-O e3 h6 Bh4 b6"),
        ("Réti Opening: Anglo-Slav", "Nf3 d5 c4 c6 b3 Nf6 g3 Bf5 Bg2 e6 Bb2 Nbd7 O-O Be7"),
        ("Réti Opening: Queen's Indian Attack", "Nf3 Nf6 c4 b6 g3 Bb7 Bg2 e6 O-O Be7 Nc3 O-O d4 d5"),
        ("Réti Opening: Nimzo-Larsen Attack", "b3 e5 Bb2 Nc6 e3 d5 Bb5 Bd6 f4 Qh4+ g3 Qe7 Nf3 f6"),
        ("Nimzo-Larsen Attack: Classical", "b3 d5 Bb2 Nf6 e3 e6 Nf3 Bd6 Be2 O-O O-O Nbd7 c4 c6 Nc3 Qe7"),
        ("King's Indian Attack", "Nf3 d5 g3 Nf6 Bg2 c6 O-O Bg4 d3 Nbd7 Nbd2 e5 e4 Be7"),
        ("Bird Opening: From's Gambit", "f4 e5 fxe5 d6 exd6 Bxd6 Nf3 g5 g3 g4 Nh4 Ne7"),
        ("Bird Opening: Dutch Variation", "f4 d5 Nf3 Nf6 e3 g6 Be2 Bg7 O-O O-O d3 c5 Qe1 Nc6"),
        ("Polish Opening", "b4 e5 Bb2 Bxb4 Bxe5 Nf6 Nf3 O-O e3 d6 Bb2 Nc6"),
        ("Grob Opening", "g4 d5 Bg2 Bxg4 c4 c6 cxd5 cxd5 Qb3 Bxe2 Nc3 Nf6"),
        ("Dunst Opening", "Nc3 d5 e4 d4 Nce2 e5 Ng3 Nf6 Bc4 Nxe4"),
        ("Hungarian Opening", "g3 d5 Bg2 e5 d3 Nf6 Nf3 Nc6 O-O Be7 Nbd2 O-O"),
        ("Zukertort Opening: Sicilian Invitation", "Nf3 c5 e4 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6"),
        ("Zukertort Opening: Queen's Gambit Invitation", "Nf3 d5 d4 Nf6 c4 e6 Nc3 Be7 Bg5 O-O e3 h6 Bh4 b6"),
        ("Queen's Pawn Game: Englund Gambit", "d4 e5 dxe5 Nc6 Nf3 Qe7 Bf4 Qb4+ Bd2 Qxb2 Bc3 Bb4"),
        ("Queen's Pawn Game: Blackmar-Diemer Gambit", "d4 d5 e4 dxe4 Nc3 Nf6 f3 exf3 Nxf3 e6 Bd3 Bb4 O-O O-O"),
        ("Queen's Pawn Game: Rapport-Jobava System", "d4 Nf6 Nc3 d5 Bf4 e6 Nb5 Bb4+ c3 Be7 e3 Na6"),
        ("Queen's Gambit: Marshall Defense", "d4 d5 c4 Nf6 cxd5 Nxd5 e4 Nb6 Nc3 Nc6 Be3 e5 d5 Nb4"),
        ("Queen's Gambit: Slav Accepted, Alapin", "d4 d5 c4 c6 Nf3 Nf6 e3 e6 Nbd2 Nbd7 Bd3 Bd6 O-O O-O e4 dxe4"),
        ("Trompowsky Attack: Classical", "d4 Nf6 Bg5 e6 e4 h6 Bxf6 Qxf6 Nc3 d6 Qd2 Nc6 O-O-O Bd7"),
        ("Trompowsky Attack: Poisoned Pawn", "d4 Nf6 Bg5 Ne4 Bf4 c5 f3 Qa5+ c3 Nf6 d5 Qb6 Qd2 Qxb2")
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
