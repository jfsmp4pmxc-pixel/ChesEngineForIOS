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

struct BoardView: View {
    let position: Position
    var flipped: Bool = false
    var lastMove: Move? = nil
    var selected: Int? = nil
    var legalTargets: Set<Int> = []
    var arrow: (from: Int, to: Int)? = nil
    var onTap: ((Int) -> Void)? = nil

    private let lightColor = Color(red: 0.93, green: 0.93, blue: 0.82)
    private let darkColor = Color(red: 0.46, green: 0.59, blue: 0.34)

    private var checkSquare: Int? {
        return position.inCheck ? position.kingSquare(position.turn) : nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8
            ZStack(alignment: .topLeading) {
                ForEach(0..<64, id: \.self) { idx in
                    let row = idx / 8
                    let col = idx % 8
                    let file = flipped ? 7 - col : col
                    let rank = flipped ? row : 7 - row
                    let sq = rank * 8 + file
                    squareView(sq: sq, row: row, col: col, cell: cell)
                        .frame(width: cell, height: cell)
                        .position(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?(sq) }
                }
                if let a = arrow {
                    ArrowShape(from: center(of: a.from, cell: cell),
                               to: center(of: a.to, cell: cell),
                               width: cell * 0.18)
                        .fill(Color.orange.opacity(0.8))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
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
            if selected == sq {
                Rectangle().fill(Color.blue.opacity(0.35))
            }
            if checkSquare == sq {
                Rectangle().fill(Color.red.opacity(0.55))
            }

            if let p = position.board[sq] {
                Text(p.glyph)
                    .font(.system(size: cell * 0.8))
                    .foregroundColor(p.side == .white ? .white : .black)
                    .shadow(color: Color.black.opacity(p.side == .white ? 0.9 : 0.0), radius: 0.8)
                    .shadow(color: Color.black.opacity(p.side == .white ? 0.5 : 0.0), radius: 1.5)
            }

            if legalTargets.contains(sq) {
                if position.board[sq] != nil {
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
