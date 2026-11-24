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
                Section(header: Text("Python runtime")) {
                    if let reason = pythonStatus {
                        Label("Not available: \(reason)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    } else {
                        Label("Embedded Python is ready", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.footnote)
                    }
                }

                Section(header: Text("Your bots"),
                        footer: Text("Bots are stored in the app's Bots folder, which is also visible in the Files app.")) {
                    if bots.bots.isEmpty {
                        Text("No bots yet").foregroundColor(.secondary)
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
                                Button("Test") { test(bot) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { bots.delete(bots.bots[i]) }
                    }
                }

                Section(header: Text("How to write a bot")) {
                    Text("""
                    Define a function get_move(fen) in a .py file. It receives the position \
                    as a FEN string and returns a move in UCI ("e2e4", "e7e8q") or SAN ("Nf3") notation.

                    Only the Python standard library is available.
                    """)
                    .font(.footnote)
                    Text("""
                    import random

                    def get_move(fen):
                        # Replace with your own logic
                        return "e2e4"
                    """)
                    .font(.system(.footnote, design: .monospaced))
                }
            }
            .navigationTitle("Bots")
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
                    message = "\(bot.name) answered \"\(text)\" from the start position. It works."
                } else {
                    message = "\(bot.name) answered \"\(text)\", which is not a legal move from the start position."
                }
            case .failure(let err):
                message = err.localizedDescription
            }
        }
    }
}
