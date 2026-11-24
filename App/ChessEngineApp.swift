import SwiftUI

@main
struct ChessEngineApp: App {
    @StateObject private var store = GameStore()
    @StateObject private var bots = BotStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(bots)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            PlayView()
                .tabItem { Label("Chơi cờ", systemImage: "gamecontroller") }
            GamesView()
                .tabItem { Label("Ván đấu", systemImage: "clock.arrow.circlepath") }
            BotsView()
                .tabItem { Label("Bot", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
        }
    }
}
