import SwiftUI
import UniformTypeIdentifiers

struct BotsView: View {
    @EnvironmentObject var bots: BotStore
    @State private var showImporter = false
    @State private var message: String? = nil
    @State private var testing: String? = nil

    private var pythonTypes: [UTType] {
        var types: [UTType] = [.plainText, .sourceCode]
        if let t = UTType(filenameExtension: "py") { types.insert(t, at: 0) }
        return types
    }

    private var pythonStatus: String? { PythonRuntime.shared.unavailableReason }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Môi trường Python")) {
                    if let reason = pythonStatus {
                        Label("Không khả dụng: \(reason)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    } else {
                        Label("Python tích hợp đã sẵn sàng", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.footnote)
                    }
                }

                Section(header: Text("Bot của bạn"),
                        footer: Text("Bot được lưu trong thư mục Bots của ứng dụng, bạn cũng thấy được trong app Tệp (Files).")) {
                    if bots.bots.isEmpty {
                        Text("Chưa có bot nào").foregroundColor(.secondary)
                    }
                    ForEach(bots.bots) { bot in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bot.name).font(.headline)
                                Text(bot.filename).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if testing == bot.id {
                                ProgressView()
                            } else {
                                Button("Thử") { test(bot) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { bots.delete(bots.bots[i]) }
                    }
                }

                Section(header: Text("Cách viết bot")) {
                    Text("""
                    Viết hàm get_move(fen) trong một file .py. Hàm nhận thế cờ dạng chuỗi FEN \
                    và trả về nước đi theo ký hiệu UCI ("e2e4", "e7e8q") hoặc SAN ("Nf3").

                    Chỉ dùng được thư viện chuẩn của Python.
                    """)
                    .font(.footnote)
                    Text("""
                    import random

                    def get_move(fen):
                        # Thay bằng logic của bạn
                        return "e2e4"
                    """)
                    .font(.system(.footnote, design: .monospaced))
                }
            }
            .navigationTitle("Bot")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: pythonTypes, allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    do {
                        try bots.importBot(from: url)
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .onAppear { bots.reload() }
        }
        .navigationViewStyle(.stack)
    }

    private func test(_ bot: PythonBotFile) {
        testing = bot.id
        Task { @MainActor in
            let res = await PythonRuntime.shared.move(botPath: bot.path, fen: Position.startFEN, timeout: 20)
            testing = nil
            switch res {
            case .success(let text):
                if Position.start.move(fromUCI: text) ?? Position.start.move(fromSAN: text) != nil {
                    message = "\(bot.name) trả lời \"\(text)\" ở thế cờ ban đầu. Bot hoạt động tốt."
                } else {
                    message = "\(bot.name) trả lời \"\(text)\", đây không phải nước đi hợp lệ ở thế cờ ban đầu."
                }
            case .failure(let err):
                message = err.localizedDescription
            }
        }
    }
}
