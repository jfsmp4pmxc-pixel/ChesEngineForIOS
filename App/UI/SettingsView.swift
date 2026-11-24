import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.profileKey) private var profileRaw = EngineProfile.lite.rawValue
    @State private var status: String? = nil
    @State private var checking = false

    private var profile: EngineProfile { EngineProfile(rawValue: profileRaw) ?? .lite }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Stockfish profile"),
                        footer: Text(profile.detail)) {
                    Picker("Profile", selection: $profileRaw) {
                        ForEach(EngineProfile.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Engine status")) {
                    Button {
                        checking = true
                        Task { @MainActor in
                            let err = await StockfishEngine.shared.checkAvailability()
                            status = err ?? "Stockfish 17.1 is running."
                            checking = false
                        }
                    } label: {
                        HStack {
                            Text("Check engine")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    if let s = status {
                        Text(s).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    Text("Chess Engine for iOS")
                    Text("Analysis uses Stockfish 17.1 (GPLv3). Move ratings and accuracy follow the same idea as chess.com's Game Review (expected-points loss) but are not identical to it.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}
