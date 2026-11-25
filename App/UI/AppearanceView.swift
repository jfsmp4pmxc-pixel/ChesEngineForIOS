import SwiftUI
import UniformTypeIdentifiers

/// Custom look: board colours, arrow colours and imported piece / badge images.
struct AppearanceView: View {
    @AppStorage(Theme.lightSquareKey) private var lightHex = Theme.defaultLight
    @AppStorage(Theme.darkSquareKey) private var darkHex = Theme.defaultDark
    @AppStorage(Theme.userArrowKey) private var userArrowHex = Theme.defaultUserArrow
    @AppStorage(Theme.bestArrowKey) private var bestArrowHex = Theme.defaultBestArrow
    @AppStorage(Theme.assetsVersionKey) private var assetsVersion = 0

    private enum Target {
        case bulkPieces
        case bulkBadges
        case slot(String)
    }

    @State private var target: Target? = nil
    @State private var showImporter = false
    @State private var message: String? = nil

    private static let pieceSlots: [(piece: Piece, title: String)] = {
        let names: [(PieceType, String)] = [(.king, "Vua"), (.queen, "Hậu"), (.rook, "Xe"),
                                            (.bishop, "Tượng"), (.knight, "Mã"), (.pawn, "Tốt")]
        var out: [(Piece, String)] = []
        for (t, n) in names { out.append((Piece(t, .white), n + " trắng")) }
        for (t, n) in names { out.append((Piece(t, .black), n + " đen")) }
        return out
    }()

    private var pieceNames: [String] { Self.pieceSlots.map { PieceArt.assetName($0.piece) } }
    private var badgeNames: [String] { MoveClass.allCases.map { $0.iconName } }

    var body: some View {
        Form {
            Section(header: Text("Màu bàn cờ")) {
                ColorPicker("Ô sáng", selection: Theme.binding($lightHex, fallback: Theme.defaultLight),
                            supportsOpacity: false)
                ColorPicker("Ô tối", selection: Theme.binding($darkHex, fallback: Theme.defaultDark),
                            supportsOpacity: false)
                preview
                Button("Về màu mặc định") {
                    lightHex = Theme.defaultLight
                    darkHex = Theme.defaultDark
                }
            }

            Section(header: Text("Màu mũi tên")) {
                ColorPicker("Mũi tên bạn vẽ", selection: Theme.binding($userArrowHex, fallback: Theme.defaultUserArrow),
                            supportsOpacity: false)
                ColorPicker("Mũi tên nước tốt nhất", selection: Theme.binding($bestArrowHex, fallback: Theme.defaultBestArrow),
                            supportsOpacity: false)
                Button("Về màu mặc định") {
                    userArrowHex = Theme.defaultUserArrow
                    bestArrowHex = Theme.defaultBestArrow
                }
            }

            Section(header: Text("Quân cờ"),
                    footer: Text("Chọn nhiều ảnh cùng lúc: tên file phải khớp ô, ví dụ wK.png, bQ.png (w/b = trắng/đen; K Q R B N P). Hỗ trợ PNG, JPG, HEIC; nên dùng ảnh PNG nền trong suốt.")) {
                Button("Nhập nhiều ảnh quân cờ…") { start(.bulkPieces) }
                ForEach(Array(Self.pieceSlots.enumerated()), id: \.offset) { _, slot in
                    let name = PieceArt.assetName(slot.piece)
                    slotRow(title: slot.title, name: name) {
                        PieceImage(piece: slot.piece, size: 34)
                    }
                }
            }

            Section(header: Text("Nhãn phân loại nước đi"),
                    footer: Text("Tên file khớp tên nhãn, ví dụ brilliant.png, blunder.png (great, best, excellent, good, book, inaccuracy, mistake, miss, blunder, forced).")) {
                Button("Nhập nhiều ảnh nhãn…") { start(.bulkBadges) }
                ForEach(MoveClass.allCases, id: \.self) { cls in
                    slotRow(title: cls.label, name: cls.iconName) {
                        ClassIcon(cls: cls).frame(width: 30, height: 30)
                    }
                }
            }

            Section {
                Button("Xóa mọi ảnh tùy chỉnh", role: .destructive) {
                    CustomAssets.remove(pieceNames + badgeNames)
                    message = "Đã xóa ảnh tùy chỉnh."
                }
            }

            if let m = message {
                Section { Text(m).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Giao diện")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            handle(result)
        }
    }

    private var preview: some View {
        let light = Color(hex: lightHex) ?? .white
        let dark = Color(hex: darkHex) ?? .green
        return HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                Rectangle().fill(i % 2 == 0 ? light : dark).aspectRatio(1, contentMode: .fit)
            }
        }
        .cornerRadius(4)
    }

    private func slotRow<Icon: View>(title: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack {
            icon()
            Text(title)
            Spacer()
            if CustomAssets.has(name) {
                Text("Tùy chỉnh").font(.caption).foregroundColor(.secondary)
                Button {
                    CustomAssets.remove([name])
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
            }
            Button("Chọn ảnh") { start(.slot(name)) }
                .buttonStyle(.borderless)
        }
    }

    private func start(_ t: Target) {
        target = t
        showImporter = true
    }

    private func handle(_ result: Result<[URL], Error>) {
        guard let t = target else { return }
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        switch t {
        case .slot(let name):
            if CustomAssets.importImage(from: urls[0], as: name) {
                message = "Đã cập nhật ảnh."
            } else {
                message = "Không đọc được ảnh đã chọn."
            }
        case .bulkPieces, .bulkBadges:
            var slots: [String] = []
            if case .bulkPieces = t { slots = pieceNames } else { slots = badgeNames }
            var ok = 0
            var skipped: [String] = []
            for u in urls {
                if let slot = CustomAssets.slot(forFile: u, among: slots),
                   CustomAssets.importImage(from: u, as: slot) {
                    ok += 1
                } else {
                    skipped.append(u.lastPathComponent)
                }
            }
            var text = "Đã nhập \(ok) ảnh."
            if !skipped.isEmpty {
                text += " Bỏ qua (tên không khớp hoặc không đọc được): " + skipped.joined(separator: ", ")
            }
            message = text
        }
    }
}
