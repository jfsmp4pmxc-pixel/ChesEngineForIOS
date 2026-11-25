import SwiftUI

enum OpponentKind: String, CaseIterable, Identifiable {
    case human = "Hai người"
    case stockfish = "Stockfish"
    case python = "Bot Python"

    var id: String { rawValue }
}

enum ColorChoice: String, CaseIterable, Identifiable {
    case white = "Trắng"
    case black = "Đen"
    case random = "Ngẫu nhiên"

    var id: String { rawValue }
}

/// Verdict on a move played in the current game (live analysis).
struct LiveMove {
    var classification: MoveClass
    var san: String
    var bestSAN: String?
}

final class PlayViewModel: ObservableObject {
    /// Arrows drawn by the player are cleared whenever a move is played or taken back.
    @Published var session = GameSession() {
        didSet {
            if oldValue.moves.count != session.moves.count { userArrows = [] }
        }
    }
    @Published var arrowMode = false
    @Published var userArrows: [BoardArrow] = []
    /// Live verdicts by move index, and moves whose analysis failed.
    @Published var live: [Int: LiveMove] = [:]
    @Published var liveFailed: Set<Int> = []
    @Published var selected: Int? = nil
    @Published var flipped = false
    @Published var thinking = false
    @Published var message: String? = nil
    @Published var pendingPromotion: (from: Int, to: Int)? = nil
    /// Moves queued while the opponent is thinking; each is played after the opponent's reply.
    @Published var premoves: [Move] = []

    // New-game configuration
    @Published var opponent: OpponentKind = .stockfish
    @Published var colorChoice: ColorChoice = .white
    @Published var levelID: Int = 3
    @Published var botFilename: String = ""

    private(set) var humanSide: Side = .white
    private var generation = UUID()
    private var recordID = UUID()
    private var started = Date()
    private var activeBot: PythonBotFile? = nil
    private var store: GameStore? = nil

    // Live analysis bookkeeping
    private var liveEvals: [Int: PositionEval] = [:]
    private var liveLosses: [Int: Double] = [:]
    private var liveGeneration = UUID()
    private var liveTail: Task<Void, Never>? = nil

    func attach(store: GameStore) {
        self.store = store
    }

    func drawArrow(_ arrow: BoardArrow) {
        userArrows.toggle(arrow)
    }

    // MARK: Live analysis

    private func moverIsOpponent(ply: Int) -> Bool {
        return opponent != .human && session.positions[ply].turn != humanSide
    }

    /// Verdict on the last move, unless it is the opponent's and those are hidden.
    func liveInfo(showOpponent: Bool) -> LiveMove? {
        let ply = session.moves.count - 1
        guard ply >= 0, let info = live[ply] else { return nil }
        if moverIsOpponent(ply: ply) && !showOpponent { return nil }
        return info
    }

    func livePending(showOpponent: Bool) -> Bool {
        let ply = session.moves.count - 1
        guard ply >= 0, live[ply] == nil, !liveFailed.contains(ply) else { return false }
        return !(moverIsOpponent(ply: ply) && !showOpponent)
    }

    private func resetLive() {
        liveGeneration = UUID()
        liveTail = nil
        live = [:]
        liveFailed = []
        liveEvals = [:]
        liveLosses = [:]
    }

    /// After taking moves back: keep the verdicts that are still valid, drop the rest.
    private func truncateLive(toMoves n: Int) {
        liveGeneration = UUID()
        liveTail = nil
        live = live.filter { $0.key < n }
        liveFailed = liveFailed.filter { $0 < n }
        liveEvals = liveEvals.filter { $0.key <= n }
        liveLosses = liveLosses.filter { $0.key < n }
    }

    /// Queues the analysis of the move just played. Moves are analysed one after another.
    private func scheduleLiveAnalysis() {
        guard Prefs.liveAnalysis else { return }
        let ply = session.moves.count - 1
        guard ply >= 0 else { return }
        let positions = session.positions
        let moves = session.moves
        let sans = session.sans
        let gen = liveGeneration
        let previous = liveTail
        let profile = Prefs.profile
        let rating = Prefs.rating

        liveTail = Task { @MainActor in
            _ = await previous?.value
            guard gen == self.liveGeneration else { return }
            await self.analyseLive(ply: ply, positions: positions, moves: moves, sans: sans,
                                   generation: gen, profile: profile, rating: rating)
        }
    }

    @MainActor
    private func analyseLive(ply: Int, positions: [Position], moves: [Move], sans: [String],
                             generation gen: UUID, profile: EngineProfile, rating: Int) async {
        do {
            let before: PositionEval
            if let cached = liveEvals[ply] {
                before = cached
            } else {
                before = try await ReviewAnalyzer.evaluate(positions[ply], profile: profile)
                guard gen == liveGeneration else { return }
                liveEvals[ply] = before
            }
            let after = try await ReviewAnalyzer.evaluate(positions[ply + 1], profile: profile)
            guard gen == liveGeneration else { return }
            liveEvals[ply + 1] = after

            let ucis = moves.prefix(ply + 1).map { $0.uci }
            let isBook = Openings.bookPlies(for: Array(ucis)) > ply
            let result = try await ReviewAnalyzer.classify(position: positions[ply],
                                                           move: moves[ply],
                                                           next: positions[ply + 1],
                                                           before: before,
                                                           after: after,
                                                           isBook: isBook,
                                                           opponentLastLoss: liveLosses[ply - 1] ?? 0,
                                                           rating: rating,
                                                           profile: profile)
            guard gen == liveGeneration else { return }
            liveLosses[ply] = result.countsTowardAverage ? result.epl : 0
            live[ply] = LiveMove(classification: result.classification,
                                 san: sans[ply],
                                 bestSAN: result.bestSAN)
        } catch {
            if gen == liveGeneration { liveFailed.insert(ply) }
        }
    }

    var level: PlayLevel {
        return PlayLevel.all.first(where: { $0.id == levelID }) ?? PlayLevel.all[3]
    }

    var isHumanTurn: Bool {
        return opponent == .human || session.position.turn == humanSide
    }

    /// Premoves can be queued (without limit) while the engine or bot is to move.
    var canPremove: Bool {
        return opponent != .human && !session.isOver && session.position.turn != humanSide
    }

    /// The position as it will be if every queued premove is played, with the human
    /// side always to move (so the next premove is chosen from pseudo-legal moves).
    private func virtualBoard(after moves: [Move]) -> Position {
        var pos = session.position
        pos.turn = humanSide
        pos.epSquare = nil
        for m in moves {
            pos = pos.make(m)
            pos.turn = humanSide
            pos.epSquare = nil
        }
        return pos
    }

    var premoveBoard: Position { return virtualBoard(after: premoves) }

    /// Faint pieces drawn where the premoves lead, and the real pieces they leave or take.
    var premoveGhosts: (ghosts: [Int: Piece], dimmed: Set<Int>) {
        guard !premoves.isEmpty else { return ([:], []) }
        let real = session.position.board
        let virt = premoveBoard.board
        var ghosts: [Int: Piece] = [:]
        var dimmed = Set<Int>()
        for sq in 0..<64 {
            let a = real[sq]
            let b = virt[sq]
            if a?.type == b?.type && a?.side == b?.side { continue }
            if let b = b { ghosts[sq] = b }
            if a != nil { dimmed.insert(sq) }
        }
        return (ghosts, dimmed)
    }

    var legalTargets: Set<Int> {
        guard let s = selected else { return [] }
        if canPremove {
            return Set(premoveBoard.pseudoMoves().filter { $0.from == s }.map { $0.to })
        }
        return Set(session.position.legalMoves().filter { $0.from == s }.map { $0.to })
    }

    func clearPremoves() {
        premoves = []
        if canPremove { selected = nil }
    }

    var opponentName: String {
        switch opponent {
        case .human: return "Người chơi 2"
        case .stockfish: return "\(StockfishEngine.versionName) · \(level.name)"
        case .python: return activeBot?.name ?? "Bot Python"
        }
    }

    var whiteName: String { humanSide == .white || opponent == .human ? "Bạn" : opponentName }
    var blackName: String { humanSide == .black || opponent == .human ? (opponent == .human ? "Người chơi 2" : "Bạn") : opponentName }

    var statusText: String {
        if session.isOver {
            return "\(Vi.termination(session.termination)) · \(session.result)"
        }
        if thinking { return "\(opponentName) đang suy nghĩ…" }
        let side = session.position.turn == .white ? "Trắng" : "Đen"
        return session.position.inCheck ? "\(side) đi · Chiếu" : "\(side) đi"
    }

    // MARK: Game flow

    func startNewGame(bots: [PythonBotFile]) {
        generation = UUID()
        thinking = false
        message = nil
        selected = nil
        pendingPromotion = nil
        premoves = []
        resetLive()
        userArrows = []
        session = GameSession()
        recordID = UUID()
        started = Date()

        switch colorChoice {
        case .white: humanSide = .white
        case .black: humanSide = .black
        case .random: humanSide = Bool.random() ? .white : .black
        }
        flipped = humanSide == .black && opponent != .human

        activeBot = nil
        if opponent == .python {
            activeBot = bots.first(where: { $0.filename == botFilename }) ?? bots.first
            if activeBot == nil {
                message = "Hãy nhập một bot Python ở tab Bot trước. Tạm thời bạn chơi với chính mình."
                opponent = .human
            }
        }
        requestOpponentMove()
    }

    private func tapPremove(_ sq: Int) {
        let pos = premoveBoard
        if let sel = selected {
            if sq == sel {
                selected = nil
                return
            }
            let candidates = pos.pseudoMoves().filter { $0.from == sel && $0.to == sq }
            if candidates.count > 1 {
                pendingPromotion = (sel, sq)
                return
            }
            if let m = candidates.first {
                premoves.append(m)
                selected = nil
                return
            }
        }
        if let p = pos.board[sq], p.side == humanSide {
            selected = sq
        } else {
            selected = nil
        }
    }

    func cancelPromotion() {
        pendingPromotion = nil
    }

    func tap(_ sq: Int) {
        guard !session.isOver, pendingPromotion == nil else { return }
        if canPremove {
            tapPremove(sq)
            return
        }
        guard !thinking, isHumanTurn else { return }
        let pos = session.position

        if let sel = selected {
            if sq == sel {
                selected = nil
                return
            }
            let candidates = pos.legalMoves().filter { $0.from == sel && $0.to == sq }
            if candidates.count > 1 {
                pendingPromotion = (sel, sq)
                return
            }
            if let m = candidates.first {
                play(m)
                return
            }
        }
        if let p = pos.board[sq], p.side == pos.turn {
            selected = sq
        } else {
            selected = nil
        }
    }

    func choosePromotion(_ type: PieceType) {
        guard let pp = pendingPromotion else { return }
        pendingPromotion = nil
        let m = Move(from: pp.from, to: pp.to, promotion: type)
        if canPremove {
            if premoveBoard.pseudoMoves().contains(m) { premoves.append(m) }
            selected = nil
            return
        }
        if session.position.legalMoves().contains(m) { play(m) }
    }

    private func play(_ move: Move) {
        selected = nil
        message = nil
        session.play(move)
        afterMove()
    }

    private func afterMove() {
        // The opponent's search is queued first so live analysis never delays its reply.
        if session.isOver {
            persist()
        } else {
            requestOpponentMove()
        }
        scheduleLiveAnalysis()
    }

    func undo() {
        guard !thinking, !session.moves.isEmpty else { return }
        generation = UUID()
        premoves = []
        let plies: Int
        if opponent == .human {
            plies = 1
        } else {
            plies = session.position.turn == humanSide ? 2 : 1
        }
        session.undo(plies: plies)
        truncateLive(toMoves: session.moves.count)
        selected = nil
        message = nil
        requestOpponentMove()
    }

    func resign() {
        guard !session.isOver else { return }
        generation = UUID()
        thinking = false
        premoves = []
        let side = opponent == .human ? session.position.turn : humanSide
        session.resign(side)
        persist()
    }

    func offerDraw() {
        guard !session.isOver, opponent == .human else { return }
        session.agreeDraw()
        persist()
    }

    func saveNow() {
        persist()
        message = "Đã lưu ván cờ."
    }

    private func persist() {
        guard let store = store, !session.moves.isEmpty else { return }
        var rec = session.record(white: whiteName, black: blackName)
        rec.id = recordID
        rec.date = started
        if let existing = store.games.first(where: { $0.id == recordID }), existing.moves == rec.moves {
            rec.review = existing.review
        }
        store.save(rec)
    }

    // MARK: Opponent

    /// Plays the first queued premove after the opponent has moved. A premove that is not
    /// legal any more cancels the whole queue.
    @MainActor
    private func runPremove(generation gen: UUID) async {
        guard !premoves.isEmpty else { return }
        if session.isOver {
            premoves = []
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard gen == generation, !premoves.isEmpty, !session.isOver else { return }
        let next = premoves.removeFirst()
        if session.position.turn == humanSide, session.position.legalMoves().contains(next) {
            selected = nil
            play(next)
        } else {
            premoves = []
        }
    }

    private func requestOpponentMove() {
        guard opponent != .human, !session.isOver, session.position.turn != humanSide else { return }
        thinking = true
        let gen = generation
        let pos = session.position
        let fen = pos.fen
        let level = self.level
        let kind = opponent
        let bot = activeBot

        Task { @MainActor in
            var chosen: Move? = nil
            var problem: String? = nil

            switch kind {
            case .stockfish:
                let r = await StockfishEngine.shared.search(fen: fen,
                                                            depth: level.depth,
                                                            movetimeMs: level.movetimeMs,
                                                            multiPV: 1,
                                                            strength: level.strength,
                                                            profile: Prefs.profile)
                if let r = r {
                    if let uci = r.bestMove { chosen = pos.move(fromUCI: uci) }
                } else {
                    problem = StockfishEngine.shared.startupError ?? "Stockfish không phản hồi."
                }
            case .python:
                if let bot = bot {
                    let res = await PythonRuntime.shared.move(botPath: bot.path, fen: fen)
                    switch res {
                    case .success(let text):
                        chosen = pos.move(fromUCI: text) ?? pos.move(fromSAN: text)
                        if chosen == nil { problem = PythonBotError.illegalMove(text).localizedDescription }
                    case .failure(let err):
                        problem = err.localizedDescription
                    }
                }
            case .human:
                break
            }

            guard gen == generation else { return }
            thinking = false
            if let m = chosen {
                session.play(m)
                afterMove()
                await runPremove(generation: gen)
            } else {
                message = problem ?? "Đối thủ không tìm được nước đi."
            }
        }
    }
}

// MARK: - View

struct PlayView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var bots: BotStore
    @StateObject private var vm = PlayViewModel()
    @State private var showSetup = false
    @State private var confirmResign = false
    @AppStorage(Prefs.liveKey) private var liveOn = false
    @AppStorage(Prefs.liveOpponentKey) private var liveOpponent = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    ArrowModeBar(isOn: $vm.arrowMode,
                                 count: vm.userArrows.count,
                                 onClear: { vm.userArrows = [] })

                    playerLabel(top: true)

                    BoardView(position: vm.session.position,
                              flipped: vm.flipped,
                              lastMove: vm.session.lastMove,
                              selected: vm.selected,
                              legalTargets: vm.legalTargets,
                              badge: liveOn ? vm.liveInfo(showOpponent: liveOpponent)?.classification : nil,
                              premoves: vm.premoves,
                              ghosts: vm.premoveGhosts.ghosts,
                              dimmed: vm.premoveGhosts.dimmed,
                              onTap: { vm.tap($0) },
                              drawingMode: vm.arrowMode,
                              userArrows: vm.userArrows,
                              onArrow: { vm.drawArrow($0) })
                        .padding(.horizontal, 8)

                    playerLabel(top: false)

                    Text(vm.statusText)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    liveLine

                    if let msg = vm.message {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if !vm.premoves.isEmpty {
                        Button {
                            vm.clearPremoves()
                        } label: {
                            Label("Hủy \(vm.premoves.count) nước đi trước", systemImage: "xmark.circle")
                        }
                        .font(.subheadline)
                    }

                    controls
                    moveList
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Chơi cờ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ván mới") { showSetup = true }
                }
            }
            .sheet(isPresented: $showSetup) {
                SetupSheet(vm: vm, isPresented: $showSetup)
                    .environmentObject(bots)
            }
            .confirmationDialog("Phong cấp thành", isPresented: Binding(
                get: { vm.pendingPromotion != nil },
                set: { if !$0 { vm.pendingPromotion = nil } })) {
                Button("Hậu") { vm.choosePromotion(.queen) }
                Button("Xe") { vm.choosePromotion(.rook) }
                Button("Tượng") { vm.choosePromotion(.bishop) }
                Button("Mã") { vm.choosePromotion(.knight) }
                Button("Hủy", role: .cancel) { vm.cancelPromotion() }
            }
            .alert("Đầu hàng ván này?", isPresented: $confirmResign) {
                Button("Đầu hàng", role: .destructive) { vm.resign() }
                Button("Hủy", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            vm.attach(store: store)
        }
    }

    /// Verdict on the move that was just played (live analysis).
    @ViewBuilder
    private var liveLine: some View {
        if liveOn, !vm.session.moves.isEmpty {
            if let info = vm.liveInfo(showOpponent: liveOpponent) {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        ClassIcon(cls: info.classification)
                            .frame(width: 20, height: 20)
                        Text("\(info.san) \(info.classification.phrase)")
                            .font(.subheadline.weight(.semibold))
                    }
                    if let best = info.bestSAN,
                       [.good, .excellent, .inaccuracy, .mistake, .miss, .blunder].contains(info.classification) {
                        Text("Tốt nhất là \(best)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            } else if vm.livePending(showOpponent: liveOpponent) {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Đang đánh giá nước đi…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func playerLabel(top: Bool) -> some View {
        // The top label belongs to the side shown at the top of the board.
        let topSide: Side = vm.flipped ? .white : .black
        let side = top ? topSide : topSide.opposite
        let name = side == .white ? vm.whiteName : vm.blackName
        return HStack {
            Circle()
                .fill(side == .white ? Color.white : Color.black)
                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(name).font(.subheadline.weight(.medium))
            Spacer()
            if vm.thinking && vm.session.position.turn == side {
                ProgressView()
            }
        }
        .padding(.horizontal, 16)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { vm.undo() } label: { Label("Đi lại", systemImage: "arrow.uturn.backward") }
                .disabled(vm.session.moves.isEmpty || vm.thinking)
            Button { vm.flipped.toggle() } label: { Label("Lật bàn cờ", systemImage: "arrow.up.arrow.down") }
            Button { vm.saveNow() } label: { Label("Lưu", systemImage: "square.and.arrow.down") }
                .disabled(vm.session.moves.isEmpty)
            Menu {
                Button("Đầu hàng", role: .destructive) { confirmResign = true }
                if vm.opponent == .human {
                    Button("Đồng ý hòa") { vm.offerDraw() }
                }
            } label: {
                Label("Thêm", systemImage: "ellipsis.circle")
            }
            .disabled(vm.session.isOver)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
    }

    private var moveList: some View {
        let sans = vm.session.sans
        let rows = (sans.count + 1) / 2
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                HStack {
                    Text("\(r + 1).").foregroundColor(.secondary).frame(width: 36, alignment: .trailing)
                    Text(sans[r * 2]).frame(width: 80, alignment: .leading)
                    if r * 2 + 1 < sans.count {
                        Text(sans[r * 2 + 1]).frame(width: 80, alignment: .leading)
                    }
                    Spacer()
                }
                .font(.system(.callout, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Setup

private struct SetupSheet: View {
    @ObservedObject var vm: PlayViewModel
    @Binding var isPresented: Bool
    @EnvironmentObject var bots: BotStore

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Đối thủ")) {
                    Picker("Đối thủ", selection: $vm.opponent) {
                        ForEach(OpponentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if vm.opponent == .stockfish {
                        Picker("Độ mạnh", selection: $vm.levelID) {
                            ForEach(PlayLevel.all) { Text($0.name).tag($0.id) }
                        }
                    }
                    if vm.opponent == .python {
                        if bots.bots.isEmpty {
                            Text("Chưa có bot nào. Hãy nhập file .py ở tab Bot.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Bot", selection: $vm.botFilename) {
                                ForEach(bots.bots) { Text($0.name).tag($0.filename) }
                            }
                        }
                    }
                }
                if vm.opponent != .human {
                    Section(header: Text("Bạn cầm quân")) {
                        Picker("Màu quân", selection: $vm.colorChoice) {
                            ForEach(ColorChoice.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Button("Bắt đầu ván cờ") {
                        vm.startNewGame(bots: bots.bots)
                        isPresented = false
                    }
                }
            }
            .navigationTitle("Ván mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { isPresented = false }
                }
            }
        }
    }
}
