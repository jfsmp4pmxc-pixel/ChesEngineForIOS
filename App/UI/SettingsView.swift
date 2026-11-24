import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.profileKey) private var profileRaw = EngineProfile.lite.rawValue
    @AppStorage(Prefs.animateKey) private var animate = true
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

                Section(header: Text("Bàn cờ")) {
                    Toggle("Hiệu ứng di chuyển quân", isOn: $animate)
                }

                Section(header: Text("Trạng thái engine")) {
                    Button {
                        checking = true
                        Task { @MainActor in
                            let err = await StockfishEngine.shared.checkAvailability()
                            status = err ?? "\(StockfishEngine.versionName) đang hoạt động."
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
                    Text("Phần phân tích dùng Stockfish 19 (GPLv3). Cách chấm nước đi và độ chính xác theo cùng ý tưởng với Game Review của chess.com (mất bao nhiêu điểm kỳ vọng) nhưng không giống hệt.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
        }
        .navigationViewStyle(.stack)
    }
}
