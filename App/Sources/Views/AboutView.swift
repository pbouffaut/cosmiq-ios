import StoreKit
import SwiftUI

struct AboutView: View {
    @StateObject private var tipJar = TipJar()

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                ZStack {
                    Theme.seaGradient
                    BubbleField(bubbleCount: 7)
                    VStack(spacing: 6) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color.foam)
                        Text("CosmiQ Companion")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Keeping the Deepblu COSMIQ+ diving\nlong after its servers went dark.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.foam)
                    }
                    .padding(.vertical, 24)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("iphone", "Your dives, settings and notes are stored on this device and — if you use iCloud — in your own private iCloud Drive, so your logbook survives reinstalling the app. There is no account and no third-party server.")
                    bullet("antenna.radiowaves.left.and.right", "Bluetooth is used solely to talk to your dive computer, and only while the app is open.")
                    bullet("location", "Your location is read only when you tap “Use Current Location” to tag a dive, and is saved only in your local logbook.")
                    bullet("chart.bar.xaxis", "No analytics, no tracking, no third-party SDKs. The app makes zero network requests.")
                    bullet("square.and.arrow.up", "Data leaves the app only when you explicitly export or share a dive.")
                }
                .font(.subheadline)
            }

            Section("Security & Safety") {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("checkmark.shield", "The app only sends the documented, community-verified commands to the dive computer, and reads values back after every change.")
                    bullet("exclamationmark.triangle", "This is unofficial, experimental software. Always verify settings on the device screen before entering the water.")
                    bullet("cross.case", "Never rely on a single instrument — or a single app — for life-safety decisions. Dive safe, carry a backup.")
                }
                .font(.subheadline)
            }

            Section("Thanks & Credits") {
                Text("This app exists thanks to the divers and developers who reverse-engineered the COSMIQ protocol and shared it with everyone:")
                    .font(.subheadline)

                Link(destination: URL(string: "https://github.com/blue-notes-robot/cosmiq5-web")!) {
                    credit("cosmiq5-web", "blue-notes-robot — settings protocol & web controller")
                }
                Link(destination: URL(string: "https://github.com/subsurface/libdc")!) {
                    credit("libdivecomputer", "Linus Torvalds & Jef Driesen — dive log protocol")
                }
                Link(destination: URL(string: "https://subsurface-divelog.org")!) {
                    credit("Subsurface", "the open-source dive log this app can export to")
                }
                Link(destination: URL(string: "https://github.com/pbouffaut/cosmiq-ios")!) {
                    credit("cosmiq-ios", "this app's source code — contributions welcome")
                }
            }

            Section("Author") {
                HStack(spacing: 12) {
                    SeaBadge(systemImage: "person.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Philippe Bouffaut")
                            .font(.headline)
                        Text("Diver · COSMIQ+ owner")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: URL(string: "mailto:pbouffaut@gmail.com")!) {
                    Label("pbouffaut@gmail.com", systemImage: "envelope")
                }
            }

            if !tipJar.products.isEmpty {
                Section {
                    Text("This app is free — no ads, no subscriptions — and it will stay that way. But air, sadly, is not. If CosmiQ Companion saved your logbook and you can afford it, you can top up my tanks. Send whatever feels right.")
                        .font(.subheadline)

                    if tipJar.phase == .thanked {
                        HStack(spacing: 10) {
                            SeaBadge(systemImage: "heart.fill")
                            Text("Tanks topped up — thank you! See you down there.")
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    ForEach(tipJar.products) { product in
                        Button {
                            Task { await tipJar.tip(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(tipJar.phase == .purchasing)
                    }
                } header: {
                    Text("Refill My Tanks")
                } footer: {
                    Text("Completely optional — a tip changes nothing in the app except the developer's air supply.")
                }
            }

            Section {
            } footer: {
                Text("Made with ❤️ for a dive computer that deserved better than a dead server.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("About")
        .task { await tipJar.load() }
    }

    private func bullet(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.ocean)
                .frame(width: 22)
            Text(text)
        }
    }

    private func credit(_ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    NavigationStack { AboutView() }
}
