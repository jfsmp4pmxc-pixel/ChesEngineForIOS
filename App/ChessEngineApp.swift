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
                .tabItem { Label("Play", systemImage: "gamecontroller") }
            GamesView()
                .tabItem { Label("Games", systemImage: "clock.arrow.circlepath") }
            BotsView()
                .tabItem { Label("Bots", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
