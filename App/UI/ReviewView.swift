import SwiftUI

final class ReviewViewModel: ObservableObject {
    @Published var record: GameRecord
    @Published var index: Int {
        didSet {
            if index != oldValue { userArrows = []; marks = [] }
        }
    }
    @Published var flipped = false
    @Published var arrowMode = false
    @Published var markMode = false
    @Published var marks: Set<Int> = []
    @Published var userArrows: [BoardArrow] = []
    @Published var progress: Double = 0
    @Published var analyzing = false
    @Published var error: String? = nil

    let positions: [Position]
    let moves: [Move]
    let sans: [String]
    private var task: Task<Void, Never>? = nil

    init(record: GameRecord) {
        self.record = record
        let r = record.replay()
        positions = r.positions
        moves = r.moves
        sans = r.sans
        index = r.moves.count
    }

    var position: Position { positions[min(index, positions.count - 1)] }
    var lastMove: Move? { index > 0 ? moves[index - 1] : nil }

    var currentReview: MoveReview? {
        guard let rv = record.review, index > 0, index - 1 < rv.moves.count else { return nil }
        return rv.moves[index - 1]
    }

    /// Arrow showing what the engine preferred to the move just played.
    var bestArrow: (from: Int, to: Int)? {
        guard let r = currentReview, let best = r.bestUCI, best != r.uci,
              [.inaccuracy, .mistake, .miss, .blunder, .good, .excellent].contains(r.classification),
              let m = positions[index - 1].move(fromUCI: best) else { return nil }
        return (m.from, m.to)
    }

    func go(to i: Int) {
        index = max(0, min(moves.count, i))
    }

    func analyze(profile: EngineProfile, rating: Int, store: GameStore) {
        guard !analyzing else { return }
        analyzing = true
        progress = 0
        error = nil
        let rec = record
        task = Task { @MainActor in
            do {
                let review = try await ReviewAnalyzer.analyze(record: rec, profile: profile, rating: rating) { p in
                    await MainActor.run { self.progress = p }
                }
                var updated = rec
                updated.review = review
                self.record = updated
                store.save(updated)
            } catch is CancellationError {
                // cancelled by the user
            } catch {
                self.error = error.localizedDescription
            }
            self.analyzing = false
        }
    }

    func cancel() {
        task?.cancel()
        StockfishEngine.shared.stop()
    }
}

struct ReviewView: View {
    @EnvironmentObject var store: GameStore
    @StateObject private var vm: ReviewViewModel
    @AppStorage(Prefs.profileKey) private var profileRaw = EngineProfile.lite.rawValue
    @State private var copied = false

    init(record: GameRecord) {
        _vm = StateObject(wrappedValue: ReviewViewModel(record: record))
    }

    private var profile: EngineProfile { EngineProfile(rawValue: profileRaw) ?? .lite }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                if let review = vm.record.review {
                    EvalBar(eval: review.evals[min(vm.index, review.evals.count - 1)], flipped: vm.flipped)
                        .padding(.horizontal, 8)
                }

                ArrowModeBar(isOn: $vm.arrowMode,
                             markOn: $vm.markMode,
                             count: vm.userArrows.count + vm.marks.count,
                             onClear: { vm.userArrows = []; vm.marks = [] })

                BoardView(position: vm.position,
                          flipped: vm.flipped,
                          lastMove: vm.lastMove,
                          arrow: vm.bestArrow,
                          badge: vm.currentReview?.classification,
                          drawingMode: vm.arrowMode,
                          userArrows: vm.userArrows,
                          onArrow: { vm.userArrows.toggle($0) },
                          markMode: vm.markMode,
                          marks: vm.marks,
                          onMark: { sq in
                              if vm.marks.contains(sq) { vm.marks.remove(sq) } else { vm.marks.insert(sq) }
                          })
                    .padding(.horizontal, 8)

                moveInfo
                navigation

                if let review = vm.record.review {
                    EvalGraph(evals: review.evals, index: vm.index)
                        .frame(height: 70)
                        .padding(.horizontal, 12)
                    summary(review)
                }

                analyzeSection
                movesList
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Xem lại")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = PGN.export(vm.record)
                    copied = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .alert("Đã chép PGN vào bộ nhớ tạm", isPresented: $copied) {
            Button("OK", role: .cancel) {}
        }
        .onDisappear { vm.cancel() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 2) {
            Text("\(vm.record.white) vs \(vm.record.black)").font(.headline)
            HStack(spacing: 6) {
                Text(vm.record.result).monospacedDigit()
                if !vm.record.termination.isEmpty { Text("· \(Vi.termination(vm.record.termination))") }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            if let opening = vm.record.review?.opening ?? Openings.name(for: vm.moves.map { $0.uci }) {
                Text(opening).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var moveInfo: some View {
        if let r = vm.currentReview {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    ClassIcon(cls: r.classification)
                        .frame(width: 26, height: 26)
                    Text("\(r.san) \(r.classification.phrase)")
                        .font(.headline)
                    if let review = vm.record.review, vm.index < review.evals.count {
                        Text(review.evals[vm.index].display)
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                if let best = r.bestSAN, r.bestUCI != r.uci,
                   [.good, .excellent, .inaccuracy, .mistake, .miss, .blunder].contains(r.classification) {
                    Text("Nước tốt nhất là \(best)").font(.footnote).foregroundColor(.secondary)
                }
            }
        } else if vm.index > 0 {
            Text(vm.sans[vm.index - 1]).font(.headline)
        } else {
            Text("Thế cờ ban đầu").font(.headline).foregroundColor(.secondary)
        }
    }

    private var navigation: some View {
        HStack(spacing: 28) {
            Button { vm.go(to: 0) } label: { Image(systemName: "backward.end.fill") }
            Button { vm.go(to: vm.index - 1) } label: { Image(systemName: "chevron.left") }
            Button { vm.flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
            Button { vm.go(to: vm.index + 1) } label: { Image(systemName: "chevron.right") }
            Button { vm.go(to: vm.moves.count) } label: { Image(systemName: "forward.end.fill") }
        }
        .font(.title2)
    }

    private func summary(_ review: GameReview) -> some View {
        VStack(spacing: 8) {
            HStack {
                accuracyBox(title: "Trắng", value: review.whiteAccuracy)
                Spacer()
                accuracyBox(title: "Đen", value: review.blackAccuracy)
            }
            ForEach(MoveClass.summaryOrder, id: \.self) { cls in
                let w = review.whiteCounts[cls.rawValue] ?? 0
                let b = review.blackCounts[cls.rawValue] ?? 0
                if w + b > 0 {
                    HStack {
                        Text("\(w)").frame(width: 36, alignment: .leading)
                        Spacer()
                        HStack(spacing: 6) {
                            ClassIcon(cls: cls)
                                .frame(width: 20, height: 20)
                            Text(cls.label).font(.subheadline)
                        }
                        Spacer()
                        Text("\(b)").frame(width: 36, alignment: .trailing)
                    }
                }
            }
            Text("\(review.engine) · độ sâu \(review.depth)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 12)
    }

    private func accuracyBox(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(String(format: "%.1f", value))
                .font(.title2.weight(.bold).monospacedDigit())
            Text("độ chính xác").font(.caption2).foregroundColor(.secondary)
        }
        .frame(width: 110)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var analyzeSection: some View {
        VStack(spacing: 8) {
            if vm.analyzing {
                ProgressView(value: vm.progress)
                    .padding(.horizontal, 24)
                Text("Đang phân tích bằng Stockfish (\(profile.title))… \(Int(vm.progress * 100))%")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("Hủy", role: .cancel) { vm.cancel() }
            } else {
                Button {
                    vm.analyze(profile: profile, rating: Prefs.rating, store: store)
                } label: {
                    Label(vm.record.review == nil ? "Phân tích ván cờ" : "Phân tích lại",
                          systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .disabled(vm.moves.isEmpty)
                Text("Cấu hình engine: \(profile.title). Đổi trong tab Cài đặt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let e = vm.error {
                Text(e).font(.footnote).foregroundColor(.red).padding(.horizontal, 24)
            }
        }
    }

    private var movesList: some View {
        let rows = (vm.moves.count + 1) / 2
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 8) {
                    Text("\(r + 1).")
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    moveButton(ply: r * 2)
                    if r * 2 + 1 < vm.moves.count {
                        moveButton(ply: r * 2 + 1)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveButton(ply: Int) -> some View {
        let cls = vm.record.review.flatMap { ply < $0.moves.count ? $0.moves[ply].classification : nil }
        let selected = vm.index == ply + 1
        return Button {
            vm.go(to: ply + 1)
        } label: {
            HStack(spacing: 4) {
                if let c = cls {
                    ClassIcon(cls: c).frame(width: 14, height: 14)
                }
                Text(vm.sans[ply])
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(selected ? .white : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 84, alignment: .leading)
            .background(selected ? Color.accentColor : Color.gray.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Eval widgets

struct EvalBar: View {
    let eval: Eval
    let flipped: Bool

    var body: some View {
        GeometryReader { geo in
            let white = CGFloat(eval.whiteWinPercent / 100)
            let barAlign: Alignment = flipped ? .trailing : .leading
            let whiteSide = white > 0.5
            let textAlign: Alignment = (whiteSide == !flipped) ? .leading : .trailing
            ZStack(alignment: barAlign) {
                Rectangle().fill(Color.black.opacity(0.85))
                Rectangle().fill(Color.white).frame(width: geo.size.width * white)
                Text(eval.display)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundColor(whiteSide ? .black : .white)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: textAlign)
            }
            .cornerRadius(4)
        }
        .frame(height: 14)
    }
}

struct EvalGraph: View {
    let evals: [Eval]
    let index: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = max(1, evals.count - 1)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.black.opacity(0.8))

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for (i, e) in evals.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(n)
                        let y = h * CGFloat(1 - e.whiteWinPercent / 100)
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.9))

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.gray.opacity(0.6), lineWidth: 0.5)

                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2, height: h)
                    .offset(x: w * CGFloat(index) / CGFloat(n) - 1)
            }
            .cornerRadius(6)
            // The graph is display-only: touches pass through it.
            .allowsHitTesting(false)
        }
    }
}
