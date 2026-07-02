import SwiftUI

@main
struct CosmiqCompanionApp: App {
    @StateObject private var ble = CosmiqBLEManager()
    @StateObject private var logbook = Logbook()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(logbook)
                .tint(.ocean)
        }
    }
}
