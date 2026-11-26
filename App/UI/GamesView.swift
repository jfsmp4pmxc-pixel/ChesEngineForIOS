import SwiftUI
import UniformTypeIdentifiers

struct GamesView: View {
    @EnvironmentObject var store: GameStore
    @State private var showPaste = false
    @State private var showImporter = false
    @State private var info: String? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var pgnTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let t = UTType(filenameExtension: "pgn") { types.insert(t, at: 0) }
        return types
    }

    var body: some View {
        NavigationView {
            Group {
                if store.games.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("Chưa có ván đấu nào được lưu").font(.headline)
                        Text("Các ván bạn chơi sẽ được lưu tự động. Bạn cũng có thể nhập file PGN.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(store.games) { game in
                            NavigationLink(destination: ReviewView(record: game)) {
                                row(game)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Ván đấu")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showPaste = true } label: { Label("Dán PGN", systemImage: "doc.on.clipboard") }
                        Button { pickPGN() } label: { Label("Nhập file PGN", systemImage: "square.and.arrow.down") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showPaste) {
                PastePGNSheet(isPresented: $showPaste) { text in
                    let n = store.importPGN(text)
                    info = n == 0 ? "Không tìm thấy ván cờ hợp lệ trong văn bản này." : "Đã nhập \(n) ván cờ."
                }
            }
            .alert(info ?? "", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    private func pickPGN() {
        FilePicker.present { urls in
            var total = 0
            for url in urls {
                if let data = try? Data(contentsOf: url) {
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    total += store.importPGN(text)
                }
            }
            info = total == 0 ? "Không tìm thấy ván cờ hợp lệ trong file đã chọn." : "Đã nhập \(total) ván cờ."
        }
    }

    private func row(_ g: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(g.white) vs \(g.black)").font(.headline).lineLimit(1)
                Spacer()
                Text(g.result).font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Text(GamesView.dateFormatter.string(from: g.date))
                Text("· \((g.moves.count + 1) / 2) nước")
                if let r = g.review {
                    Text("· \(Int(r.whiteAccuracy.rounded()))% / \(Int(r.blackAccuracy.rounded()))%")
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct PastePGNSheet: View {
    @Binding var isPresented: Bool
    var onImport: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dán một hoặc nhiều ván cờ theo định dạng PGN.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
            }
            .padding()
            .navigationTitle("Dán PGN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Nhập") {
                        onImport(text)
                        isPresented = false
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
