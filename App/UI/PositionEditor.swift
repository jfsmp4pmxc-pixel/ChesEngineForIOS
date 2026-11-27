import SwiftUI

/// Rules a custom starting position has to meet before a game can start from it.
enum PositionRules {
    /// Why `pos` cannot be played from, or nil when it is fine.
    static func problem(in pos: Position) -> String? {
        var kings = [0, 0]
        for sq in 0..<64 {
            guard let p = pos.board[sq] else { continue }
            let s = p.side.rawValue
            if p.type == .king { kings[s] += 1 }
            if p.type == .pawn {
                if sq < 8 || sq >= 56 {
                    return "Tốt không được đứng ở hàng 1 hoặc hàng 8 (đến hàng cuối là phải phong cấp)."
                }
            }
        }
        if kings[0] != 1 { return "Phải có đúng một vua trắng." }
        if kings[1] != 1 { return "Phải có đúng một vua đen." }

        guard let wk = pos.kingSquare(.white), let bk = pos.kingSquare(.black) else { return "Thiếu vua." }
        if abs(wk % 8 - bk % 8) <= 1 && abs(wk / 8 - bk / 8) <= 1 {
            return "Hai vua không được đứng sát nhau."
        }
        if let k = pos.kingSquare(pos.turn.opposite), pos.isAttacked(k, by: pos.turn) {
            let name = pos.turn.opposite == .white ? "trắng" : "đen"
            return "Vua \(name) đang bị chiếu nhưng không phải lượt của bên \(name). Hãy đổi bên đi trước hoặc sửa lại thế cờ."
        }
        if pos.status() == .insufficientMaterial { return "Không đủ quân để chiếu hết (hòa ngay)." }
        // Whichever side is given the move, it must have a legal move.
        for side in [Side.white, Side.black] {
            var test = pos
            test.turn = side
            test.epSquare = nil
            if test.legalMoves().isEmpty {
                let name = side == .white ? "trắng" : "đen"
                return test.inCheck
                    ? "Nếu bên \(name) đi trước thì bị chiếu hết, không còn nước hợp lệ. Hãy sửa lại thế cờ."
                    : "Nếu bên \(name) đi trước thì bị bí cờ (không có nước hợp lệ nào), tức là hòa. Hãy sửa lại thế cờ."
            }
        }
        return nil
    }
}

/// Lets the player set up any position and use it as the start of a new game.
struct PositionEditorView: View {
    /// FEN the next game starts from (nil = the usual start position).
    @Binding var customFEN: String?
    @Environment(\.presentationMode) private var presentationMode

    private enum Tool: Equatable {
        case piece(Piece)
        case eraser
    }

    @State private var board: [Piece?]
    @State private var turn: Side
    @State private var whiteShort: Bool
    @State private var whiteLong: Bool
    @State private var blackShort: Bool
    @State private var blackLong: Bool
    @State private var tool: Tool = .piece(Piece(.pawn, .white))
    @State private var flipped = false
    @State private var message: String? = nil
    @State private var fenText = ""

    init(customFEN: Binding<String?>) {
        _customFEN = customFEN
        let pos = customFEN.wrappedValue.flatMap { Position(fen: $0) } ?? Position.start
        _board = State(initialValue: pos.board)
        _turn = State(initialValue: pos.turn)
        _whiteShort = State(initialValue: pos.castleWK)
        _whiteLong = State(initialValue: pos.castleWQ)
        _blackShort = State(initialValue: pos.castleBK)
        _blackLong = State(initialValue: pos.castleBQ)
    }

    // MARK: Position

    private func has(_ piece: Piece, at sq: Int) -> Bool { board[sq] == piece }

    private var canWhiteShort: Bool { has(Piece(.king, .white), at: 4) && has(Piece(.rook, .white), at: 7) }
    private var canWhiteLong: Bool { has(Piece(.king, .white), at: 4) && has(Piece(.rook, .white), at: 0) }
    private var canBlackShort: Bool { has(Piece(.king, .black), at: 60) && has(Piece(.rook, .black), at: 63) }
    private var canBlackLong: Bool { has(Piece(.king, .black), at: 60) && has(Piece(.rook, .black), at: 56) }

    private func makePosition() -> Position {
        var p = Position()
        p.board = board
        p.turn = turn
        p.castleWK = whiteShort && canWhiteShort
        p.castleWQ = whiteLong && canWhiteLong
        p.castleBK = blackShort && canBlackShort
        p.castleBQ = blackLong && canBlackLong
        p.epSquare = nil
        p.halfmove = 0
        p.fullmove = 1
        return p
    }

    // MARK: Editing

    private func tap(_ sq: Int) {
        message = nil
        switch tool {
        case .eraser:
            board[sq] = nil
        case .piece(let piece):
            // Placing the piece that is already there removes it.
            if board[sq] == piece { board[sq] = nil; return }
            if piece.type == .pawn && (sq < 8 || sq >= 56) {
                message = "Không thể đặt tốt ở hàng 1 hoặc hàng 8: đến đó là phong cấp rồi."
                return
            }
            if piece.type == .king {
                var probe = board
                for i in 0..<64 where probe[i] == piece { probe[i] = nil }
                probe[sq] = nil
                var pos = Position()
                pos.board = probe
                if pos.isAttacked(sq, by: piece.side.opposite) {
                    message = "Không được đặt vua vào ô đang bị chiếu."
                    return
                }
                // Not next to the other king.
                if let other = pos.kingSquare(piece.side.opposite),
                   abs(other % 8 - sq % 8) <= 1 && abs(other / 8 - sq / 8) <= 1 {
                    message = "Hai vua không được đứng sát nhau."
                    return
                }
                // A side has only one king: moving it picks up the old one.
                for i in 0..<64 where board[i] == piece { board[i] = nil }
            }
            board[sq] = piece
        }
    }

    private func clearBoard() {
        board = Array(repeating: nil, count: 64)
        message = nil
    }

    private func resetBoard() {
        let p = Position.start
        board = p.board
        turn = .white
        whiteShort = true; whiteLong = true; blackShort = true; blackLong = true
        message = nil
    }

    private func loadFEN() {
        let text = fenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let p = Position(fen: text) else {
            message = "FEN không hợp lệ."
            return
        }
        board = p.board
        turn = p.turn
        whiteShort = p.castleWK; whiteLong = p.castleWQ
        blackShort = p.castleBK; blackLong = p.castleBQ
        message = nil
    }

    private func use() {
        let pos = makePosition()
        if let problem = PositionRules.problem(in: pos) {
            message = problem
            return
        }
        customFEN = pos == Position.start ? nil : pos.fen
        presentationMode.wrappedValue.dismiss()
    }

    // MARK: View

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BoardView(position: makePosition(),
                          flipped: flipped,
                          onTap: { tap($0) })
                    .padding(.horizontal, 8)

                palette

                if let m = message {
                    Text(m)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Bên đi trước", selection: $turn) {
                        Text("Trắng đi").tag(Side.white)
                        Text("Đen đi").tag(Side.black)
                    }
                    .pickerStyle(.segmented)

                    Text("Quyền nhập thành").font(.subheadline.weight(.semibold))
                    Toggle("Trắng: nhập thành gần (O-O)", isOn: $whiteShort).disabled(!canWhiteShort)
                    Toggle("Trắng: nhập thành xa (O-O-O)", isOn: $whiteLong).disabled(!canWhiteLong)
                    Toggle("Đen: nhập thành gần (O-O)", isOn: $blackShort).disabled(!canBlackShort)
                    Toggle("Đen: nhập thành xa (O-O-O)", isOn: $blackLong).disabled(!canBlackLong)
                    Text("Chỉ bật được khi vua và xe còn đúng ô ban đầu.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Button("Xóa hết") { clearBoard() }
                    Button("Ban đầu") { resetBoard() }
                    Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nạp từ FEN").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Dán chuỗi FEN", text: $fenText)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Button("Nạp") { loadFEN() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)

                Button { use() } label: {
                    Text("Dùng thế cờ này")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)

                rules
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Thế cờ tuỳ chỉnh")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var palette: some View {
        VStack(spacing: 6) {
            ForEach([Side.white, Side.black], id: \.rawValue) { side in
                HStack(spacing: 4) {
                    ForEach([PieceType.king, .queen, .rook, .bishop, .knight, .pawn], id: \.rawValue) { type in
                        let piece = Piece(type, side)
                        Button { tool = .piece(piece) } label: {
                            PieceImage(piece: piece, size: 38)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(tool == .piece(piece) ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button { tool = .eraser } label: {
                Label("Cục tẩy", systemImage: "eraser")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(tool == .eraser ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Quy tắc").font(.caption.weight(.semibold))
            Text("• Chọn quân rồi chạm ô để đặt; chạm lại cùng quân để gỡ.\n• Phải có đúng một vua trắng và một vua đen, không đứng sát nhau và không đặt vào ô bị chiếu.\n• Không đặt tốt ở hàng 1 hoặc hàng 8. Số tốt và số quân khác không bị giới hạn (chỉ giới hạn vua).\n• Bên không đến lượt không được đang bị chiếu.\n• Dù cho bên nào đi trước, bên đó cũng phải có ít nhất một nước hợp lệ (không chiếu hết, không bí cờ); không đủ quân để chiếu hết cũng không dùng được.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
