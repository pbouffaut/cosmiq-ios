import SwiftUI

@main
struct CosmiqCompanionApp: App {
    @StateObject private var ble = CosmiqBLEManager()
    @StateObject private var logbook = Logbook()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(ble)
                    .environmentObject(logbook)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .tint(.ocean)
            .task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.6)) {
                    showSplash = false
                }
            }
        }
    }
}
