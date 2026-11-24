import SwiftUI

enum OpponentKind: String, CaseIterable, Identifiable {
    case human = "Two players"
    case stockfish = "Stockfish"
    case python = "Python bot"

    var id: String { rawValue }
}

enum ColorChoice: String, CaseIterable, Identifiable {
    case white = "White"
    case black = "Black"
    case random = "Random"

    var id: String { rawValue }
}

final class PlayViewModel: ObservableObject {
    @Published var session = GameSession()
    @Published var selected: Int? = nil
    @Published var flipped = false
    @Published var thinking = false
    @Published var message: String? = nil
    @Published var pendingPromotion: (from: Int, to: Int)? = nil

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

    func attach(store: GameStore) {
        self.store = store
    }

    var level: PlayLevel {
        return PlayLevel.all.first(where: { $0.id == levelID }) ?? PlayLevel.all[3]
    }

    var isHumanTurn: Bool {
        return opponent == .human || session.position.turn == humanSide
    }

    var legalTargets: Set<Int> {
        guard let s = selected else { return [] }
        return Set(session.position.legalMoves().filter { $0.from == s }.map { $0.to })
    }

    var opponentName: String {
        switch opponent {
        case .human: return "Player 2"
        case .stockfish: return "Stockfish 17.1 · \(level.name)"
        case .python: return activeBot?.name ?? "Python bot"
        }
    }

    var whiteName: String { humanSide == .white || opponent == .human ? "You" : opponentName }
    var blackName: String { humanSide == .black || opponent == .human ? (opponent == .human ? "Player 2" : "You") : opponentName }

    var statusText: String {
        if session.isOver {
            return "\(session.termination) · \(session.result)"
        }
        if thinking { return "\(opponentName) is thinking…" }
        let side = session.position.turn == .white ? "White" : "Black"
        return session.position.inCheck ? "\(side) to move · Check" : "\(side) to move"
    }

    // MARK: Game flow

    func startNewGame(bots: [PythonBotFile]) {
        generation = UUID()
        thinking = false
        message = nil
        selected = nil
        pendingPromotion = nil
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
                message = "Import a Python bot in the Bots tab first. Playing against yourself for now."
                opponent = .human
            }
        }
        requestOpponentMove()
    }

    func tap(_ sq: Int) {
        guard !session.isOver, !thinking, isHumanTurn, pendingPromotion == nil else { return }
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
        if session.position.legalMoves().contains(m) { play(m) }
    }

    private func play(_ move: Move) {
        selected = nil
        message = nil
        session.play(move)
        afterMove()
    }

    private func afterMove() {
        if session.isOver {
            persist()
        } else {
            requestOpponentMove()
        }
    }

    func undo() {
        guard !thinking, !session.moves.isEmpty else { return }
        generation = UUID()
        let plies: Int
        if opponent == .human {
            plies = 1
        } else {
            plies = session.position.turn == humanSide ? 2 : 1
        }
        session.undo(plies: plies)
        selected = nil
        message = nil
        requestOpponentMove()
    }

    func resign() {
        guard !session.isOver else { return }
        generation = UUID()
        thinking = false
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
        message = "Game saved."
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
                    problem = StockfishEngine.shared.startupError ?? "Stockfish failed to answer."
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
            } else {
                message = problem ?? "The opponent could not find a move."
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    playerLabel(top: true)

                    BoardView(position: vm.session.position,
                              flipped: vm.flipped,
                              lastMove: vm.session.lastMove,
                              selected: vm.selected,
                              legalTargets: vm.legalTargets,
                              onTap: { vm.tap($0) })
                        .padding(.horizontal, 8)

                    playerLabel(top: false)

                    Text(vm.statusText)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let msg = vm.message {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    controls
                    moveList
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New game") { showSetup = true }
                }
            }
            .sheet(isPresented: $showSetup) {
                SetupSheet(vm: vm, isPresented: $showSetup)
                    .environmentObject(bots)
            }
            .confirmationDialog("Promote to", isPresented: Binding(
                get: { vm.pendingPromotion != nil },
                set: { if !$0 { vm.pendingPromotion = nil } })) {
                Button("Queen") { vm.choosePromotion(.queen) }
                Button("Rook") { vm.choosePromotion(.rook) }
                Button("Bishop") { vm.choosePromotion(.bishop) }
                Button("Knight") { vm.choosePromotion(.knight) }
                Button("Cancel", role: .cancel) { vm.pendingPromotion = nil }
            }
            .alert("Resign this game?", isPresented: $confirmResign) {
                Button("Resign", role: .destructive) { vm.resign() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            vm.attach(store: store)
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
            Button { vm.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(vm.session.moves.isEmpty || vm.thinking)
            Button { vm.flipped.toggle() } label: { Label("Flip", systemImage: "arrow.up.arrow.down") }
            Button { vm.saveNow() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(vm.session.moves.isEmpty)
            Menu {
                Button("Resign", role: .destructive) { confirmResign = true }
                if vm.opponent == .human {
                    Button("Agree a draw") { vm.offerDraw() }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
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
                Section(header: Text("Opponent")) {
                    Picker("Opponent", selection: $vm.opponent) {
                        ForEach(OpponentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if vm.opponent == .stockfish {
                        Picker("Strength", selection: $vm.levelID) {
                            ForEach(PlayLevel.all) { Text($0.name).tag($0.id) }
                        }
                    }
                    if vm.opponent == .python {
                        if bots.bots.isEmpty {
                            Text("No bots yet. Import a .py file in the Bots tab.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Bot", selection: $vm.botFilename) {
                                ForEach(bots.bots) { Text($0.name).tag($0.filename) }
                            }
                        }
                    }
                }
                if vm.opponent != .human {
                    Section(header: Text("You play")) {
                        Picker("Colour", selection: $vm.colorChoice) {
                            ForEach(ColorChoice.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Button("Start game") {
                        vm.startNewGame(bots: bots.bots)
                        isPresented = false
                    }
                }
            }
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
