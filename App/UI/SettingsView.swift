import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.profileKey) private var profileRaw = EngineProfile.lite.rawValue
    @State private var status: String? = nil
    @State private var checking = false

    private var profile: EngineProfile { EngineProfile(rawValue: profileRaw) ?? .lite }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Cấu hình Stockfish"),
                        footer: Text(profile.detail)) {
                    Picker("Cấu hình", selection: $profileRaw) {
                        ForEach(EngineProfile.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Trạng thái engine")) {
                    Button {
                        checking = true
                        Task { @MainActor in
                            let err = await StockfishEngine.shared.checkAvailability()
                            status = err ?? "Stockfish 17.1 đang hoạt động."
                            checking = false
                        }
                    } label: {
                        HStack {
                            Text("Kiểm tra engine")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    if let s = status {
                        Text(s).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Giới thiệu")) {
                    Text("Chess Engine for iOS")
                    Text("Phần phân tích dùng Stockfish 17.1 (GPLv3). Cách chấm nước đi và độ chính xác theo cùng ý tưởng với Game Review của chess.com (mất bao nhiêu điểm kỳ vọng) nhưng không giống hệt.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
        }
        .navigationViewStyle(.stack)
    }
}
