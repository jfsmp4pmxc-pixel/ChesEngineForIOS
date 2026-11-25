import SwiftUI

/// Filled arrow between two points (used to show the engine's best move).
struct ArrowShape: Shape {
    var from: CGPoint
    var to: CGPoint
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len
        let nx = -uy
        let ny = ux
        let headLen = width * 2.2
        let headWidth = width * 2.6
        let base = CGPoint(x: to.x - ux * headLen, y: to.y - uy * headLen)

        func pt(_ origin: CGPoint, _ k: CGFloat) -> CGPoint {
            return CGPoint(x: origin.x + nx * k, y: origin.y + ny * k)
        }

        p.move(to: pt(from, width / 2))
        p.addLine(to: pt(base, width / 2))
        p.addLine(to: pt(base, headWidth / 2))
        p.addLine(to: to)
        p.addLine(to: pt(base, -headWidth / 2))
        p.addLine(to: pt(base, -width / 2))
        p.addLine(to: pt(from, -width / 2))
        p.closeSubpath()
        return p
    }
}

/// An arrow the player drew on the board (any square to any square).
struct BoardArrow: Hashable {
    var from: Int
    var to: Int
}

extension Array where Element == BoardArrow {
    /// Adds the arrow, or removes it if the same arrow is already there.
    mutating func toggle(_ arrow: BoardArrow) {
        if let i = firstIndex(of: arrow) {
            remove(at: i)
        } else {
            append(arrow)
        }
    }
}

/// Switch that turns arrow drawing on or off, shown above a board.
struct ArrowModeBar: View {
    @Binding var isOn: Bool
    let count: Int
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Toggle(isOn: $isOn) {
                    Label("Vẽ mũi tên", systemImage: "arrow.up.right")
                }
                .toggleStyle(.button)

                if count > 0 {
                    Button(action: onClear) {
                        Label("Xóa mũi tên", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            if isOn {
                Text("Kéo từ ô này sang ô khác, hoặc chạm hai ô liên tiếp. Vẽ lại cùng mũi tên để xóa nó.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
    }
}

/// A piece that is sliding from one square to another.
private struct Slide: Identifiable {
    let id = UUID()
    let piece: Piece
    let from: Int
    let to: Int
    /// The piece taken on the destination square, drawn until the mover arrives.
    var captured: Piece? = nil
}

/// Draws a piece on its destination square and glides it in from where it came from.
/// The offset is computed from the clock on every frame, so it does not depend on
/// SwiftUI's implicit animations.
private struct SlidingPiece: View {
    let piece: Piece
    let size: CGFloat
    /// Distance from the destination back to the origin, in points.
    let dx: CGFloat
    let dy: CGFloat
    let start: Date
    let duration: Double

    var body: some View {
        TimelineView(.animation) { context in
            let raw = duration <= 0 ? 1.0 : context.date.timeIntervalSince(start) / duration
            let t = min(1.0, max(0.0, raw))
            // Ease in and out.
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            PieceImage(piece: piece, size: size)
                .offset(x: dx * CGFloat(1 - eased), y: dy * CGFloat(1 - eased))
        }
    }
}

struct BoardView: View {
    let position: Position
    var flipped: Bool = false
    var lastMove: Move? = nil
    var selected: Int? = nil
    var legalTargets: Set<Int> = []
    var arrow: (from: Int, to: Int)? = nil
    /// Quality of the last move; drawn in the top-right corner of its destination square.
    var badge: MoveClass? = nil
    /// Queued premoves (their squares are tinted).
    var premoves: [Move] = []
    /// Pieces drawn faintly on the squares the premoves lead to.
    var ghosts: [Int: Piece] = [:]
    /// Squares whose real piece is drawn faintly because a premove moves or takes it.
    var dimmed: Set<Int> = []
    var onTap: ((Int) -> Void)? = nil
    /// While drawing, taps and drags make arrows instead of moving pieces.
    var drawingMode: Bool = false
    var userArrows: [BoardArrow] = []
    var onArrow: ((BoardArrow) -> Void)? = nil

    @AppStorage(Prefs.animateKey) private var animate = true
    @AppStorage(Prefs.slideDurationKey) private var slideDuration = Prefs.defaultSlideDuration
    @State private var pendingArrowStart: Int? = nil

    /// The position that is currently drawn. It follows `position` one step later so a
    /// move can be animated from the old squares to the new ones.
    @State private var shown: Position
    @State private var shownMove: Move?
    @State private var slides: [Slide] = []
    @State private var slideStart = Date()
    @State private var slideToken = UUID()

    private let lightColor = Color(red: 0.93, green: 0.93, blue: 0.82)
    private let darkColor = Color(red: 0.46, green: 0.59, blue: 0.34)

    init(position: Position,
         flipped: Bool = false,
         lastMove: Move? = nil,
         selected: Int? = nil,
         legalTargets: Set<Int> = [],
         arrow: (from: Int, to: Int)? = nil,
         badge: MoveClass? = nil,
         premoves: [Move] = [],
         ghosts: [Int: Piece] = [:],
         dimmed: Set<Int> = [],
         onTap: ((Int) -> Void)? = nil,
         drawingMode: Bool = false,
         userArrows: [BoardArrow] = [],
         onArrow: ((BoardArrow) -> Void)? = nil) {
        self.position = position
        self.flipped = flipped
        self.lastMove = lastMove
        self.selected = selected
        self.legalTargets = legalTargets
        self.arrow = arrow
        self.badge = badge
        self.premoves = premoves
        self.ghosts = ghosts
        self.dimmed = dimmed
        self.onTap = onTap
        self.drawingMode = drawingMode
        self.userArrows = userArrows
        self.onArrow = onArrow
        _shown = State(initialValue: position)
        _shownMove = State(initialValue: lastMove)
    }

    private var checkSquare: Int? {
        return shown.inCheck ? shown.kingSquare(shown.turn) : nil
    }

    private var hiddenSquares: Set<Int> {
        return Set(slides.map { $0.to })
    }

    /// Pieces that were just taken, still shown on their square while the capturer glides in.
    private var capturedDuringSlide: [Int: Piece] {
        var result: [Int: Piece] = [:]
        for s in slides {
            if let c = s.captured { result[s.to] = c }
        }
        return result
    }

    private var premoveSquares: Set<Int> {
        return Set(premoves.flatMap { [$0.from, $0.to] })
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8
            ZStack(alignment: .topLeading) {
                // The squares are laid out with stacks (not `.position`), so every
                // square gets its own tap area.
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let sq = square(row: row, col: col)
                                squareView(sq: sq, row: row, col: col, cell: cell)
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onTap?(sq) }
                            }
                        }
                    }
                }
                ForEach(userArrows, id: \.self) { a in
                    ArrowShape(from: center(of: a.from, cell: cell),
                               to: center(of: a.to, cell: cell),
                               width: cell * 0.16)
                        .fill(Color(red: 0.15, green: 0.65, blue: 0.30).opacity(0.78))
                        .allowsHitTesting(false)
                }
                if let a = arrow {
                    ArrowShape(from: center(of: a.from, cell: cell),
                               to: center(of: a.to, cell: cell),
                               width: cell * 0.18)
                        .fill(Color.orange.opacity(0.8))
                        .allowsHitTesting(false)
                }
                ForEach(slides) { s in
                    let a = center(of: s.from, cell: cell)
                    let b = center(of: s.to, cell: cell)
                    SlidingPiece(piece: s.piece,
                                 size: cell,
                                 dx: a.x - b.x,
                                 dy: a.y - b.y,
                                 start: slideStart,
                                 duration: slideDuration)
                        .position(x: b.x, y: b.y)
                        .allowsHitTesting(false)
                }
                if drawingMode {
                    // Sits above the squares so taps and drags draw instead of moving pieces.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let a = squareAt(value.startLocation, cell: cell)
                                    let b = squareAt(value.location, cell: cell)
                                    arrowGesture(from: a, to: b)
                                }
                        )
                }
                if let b = badge, let lm = lastMove {
                    let d = cell * 0.46
                    let c = center(of: lm.to, cell: cell)
                    let x = min(max(c.x + cell / 2 - d * 0.40, d / 2), size - d / 2)
                    let y = min(max(c.y - cell / 2 + d * 0.40, d / 2), size - d / 2)
                    ClassIcon(cls: b)
                        .frame(width: d, height: d)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: position) { newPosition in
            positionChanged(to: newPosition)
        }
        .onChange(of: drawingMode) { _ in
            pendingArrowStart = nil
        }
    }

    // MARK: Arrow drawing

    private func squareAt(_ point: CGPoint, cell: CGFloat) -> Int {
        let col = min(7, max(0, Int(point.x / cell)))
        let row = min(7, max(0, Int(point.y / cell)))
        return square(row: row, col: col)
    }

    /// A drag draws an arrow at once. Two taps do too: the first picks the start square,
    /// the second (on another square) the end.
    private func arrowGesture(from a: Int, to b: Int) {
        if a != b {
            pendingArrowStart = nil
            onArrow?(BoardArrow(from: a, to: b))
            return
        }
        if let start = pendingArrowStart {
            if start != a { onArrow?(BoardArrow(from: start, to: a)) }
            pendingArrowStart = nil
        } else {
            pendingArrowStart = a
        }
    }

    // MARK: Animation

    private func positionChanged(to new: Position) {
        let old = shown
        var newSlides: [Slide] = []
        if animate, slideDuration > 0.01 {
            if let move = lastMove, old.board[move.from] != nil, old.make(move) == new {
                newSlides = BoardView.makeSlides(move: move, old: old, new: new, forward: true)
            } else if let prev = shownMove, new.board[prev.from] != nil, new.make(prev) == old {
                newSlides = BoardView.makeSlides(move: prev, old: old, new: new, forward: false)
            }
        }
        let token = UUID()
        slideToken = token
        slideStart = Date()
        shown = new
        shownMove = lastMove
        slides = newSlides
        guard !newSlides.isEmpty else { return }
        // Drop the sliding pieces once they have arrived (unless a newer move replaced them).
        let wait = slideDuration + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if slideToken == token { slides = [] }
        }
    }

    /// The pieces that travel when `move` is played (`forward`) or taken back.
    private static func makeSlides(move: Move, old: Position, new: Position, forward: Bool) -> [Slide] {
        var result: [Slide] = []
        // The moving piece stands on the destination after the move, or on the origin
        // square when the move is taken back.
        let mover = forward ? new.board[move.to] : new.board[move.from]
        if let p = mover {
            var slide = Slide(piece: p,
                              from: forward ? move.from : move.to,
                              to: forward ? move.to : move.from)
            if forward, let taken = old.board[move.to], taken.side != p.side {
                slide.captured = taken
            }
            result.append(slide)
        }
        // Castling moves the rook as well.
        let king = forward ? old.board[move.from] : new.board[move.from]
        if let k = king, k.type == .king, abs(move.to - move.from) == 2 {
            let rank = move.from / 8
            let kingside = move.to > move.from
            let rookFrom = rank * 8 + (kingside ? 7 : 0)
            let rookTo = rank * 8 + (kingside ? 5 : 3)
            let rook = forward ? new.board[rookTo] : new.board[rookFrom]
            if let r = rook {
                result.append(Slide(piece: r,
                                    from: forward ? rookFrom : rookTo,
                                    to: forward ? rookTo : rookFrom))
            }
        }
        return result
    }

    // MARK: Layout

    /// Square index for a screen row / column (row 0 is the top of the board).
    private func square(row: Int, col: Int) -> Int {
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        return rank * 8 + file
    }

    private func center(of sq: Int, cell: CGFloat) -> CGPoint {
        let file = sq % 8
        let rank = sq / 8
        let col = flipped ? 7 - file : file
        let row = flipped ? rank : 7 - rank
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    @ViewBuilder
    private func squareView(sq: Int, row: Int, col: Int, cell: CGFloat) -> some View {
        let light = (row + col) % 2 == 0
        ZStack {
            Rectangle().fill(light ? lightColor : darkColor)

            if let lm = lastMove, lm.from == sq || lm.to == sq {
                Rectangle().fill(Color.yellow.opacity(0.4))
            }
            if premoveSquares.contains(sq) {
                Rectangle().fill(Color.red.opacity(0.32))
            }
            if selected == sq {
                Rectangle().fill(Color.blue.opacity(0.35))
            }
            if pendingArrowStart == sq {
                Rectangle().fill(Color.green.opacity(0.45))
            }
            if checkSquare == sq {
                Rectangle().fill(Color.red.opacity(0.55))
            }

            if let p = shown.board[sq], !hiddenSquares.contains(sq) {
                PieceImage(piece: p, size: cell)
                    .opacity(dimmed.contains(sq) ? 0.35 : 1)
            } else if let c = capturedDuringSlide[sq] {
                PieceImage(piece: c, size: cell)
            }
            if let g = ghosts[sq] {
                PieceImage(piece: g, size: cell)
                    .opacity(0.65)
            }

            if legalTargets.contains(sq) {
                if shown.board[sq] != nil {
                    Circle().stroke(Color.black.opacity(0.35), lineWidth: cell * 0.09)
                        .padding(cell * 0.04)
                } else {
                    Circle().fill(Color.black.opacity(0.25))
                        .frame(width: cell * 0.3, height: cell * 0.3)
                }
            }

            if col == 0 {
                Text(String(sq / 8 + 1))
                    .font(.system(size: cell * 0.2, weight: .semibold))
                    .foregroundColor(light ? darkColor : lightColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }
            if row == 7 {
                Text(String(Array("abcdefgh")[sq % 8]))
                    .font(.system(size: cell * 0.2, weight: .semibold))
                    .foregroundColor(light ? darkColor : lightColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }
        }
    }
}
