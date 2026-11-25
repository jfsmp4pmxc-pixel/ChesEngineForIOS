import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.profileKey) private var profileRaw = EngineProfile.lite.rawValue
    @AppStorage(Prefs.animateKey) private var animate = true
    @AppStorage(Prefs.slideDurationKey) private var slideDuration = Prefs.defaultSlideDuration
    @AppStorage(Prefs.ratingKey) private var rating = Prefs.defaultRating
    @AppStorage(Prefs.liveKey) private var live = false
    @AppStorage(Prefs.liveOpponentKey) private var liveOpponent = true
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

                Section(header: Text("Chấm điểm nước đi"),
                        footer: Text("Elo càng thấp thì càng được châm chước sai sót nhỏ, và nước hy sinh quân dễ được tính là thiên tài hơn. Từ 2000 trở lên phải hy sinh ít nhất 2 tốt. Chỉ ảnh hưởng đến lần phân tích tiếp theo.")) {
                    Stepper(value: $rating, in: 400...3000, step: 50) {
                        HStack {
                            Text("Elo của bạn")
                            Spacer()
                            Text("\(rating)").foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                }

                Section(header: Text("Phân tích trực tiếp"),
                        footer: Text("Mỗi nước vừa đi sẽ được Stockfish đánh giá và gắn nhãn ngay khi đang chơi (Tuyệt vời, Sai lầm…). Dùng nhiều pin và CPU hơn, và nước phản hồi của máy có thể chậm đi một chút.")) {
                    Toggle("Phân tích nước đi trực tiếp", isOn: $live)
                    Toggle("Cả nước đi của đối thủ", isOn: $liveOpponent)
                        .disabled(!live)
                }

                Section(header: Text("Bàn cờ")) {
                    Toggle("Hiệu ứng di chuyển quân", isOn: $animate)
                    if animate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Thời gian lướt")
                                Spacer()
                                Text(String(format: "%.2f giây", slideDuration))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $slideDuration, in: 0.05...1.0, step: 0.05)
                        }
                    }
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
