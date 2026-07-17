import Foundation
import StoreKit

/// Consumable "tank refill" tips, per App Store guideline 3.1.1: voluntary
/// support goes through in-app purchase, and nothing in the app unlocks.
@MainActor
final class TipJar: ObservableObject {
    /// Consumable product IDs configured in App Store Connect, smallest first.
    static let productIDs = [
        "com.pbouffaut.cosmiq.tip.pony",
        "com.pbouffaut.cosmiq.tip.al80",
        "com.pbouffaut.cosmiq.tip.twinset",
    ]

    enum Phase: Equatable {
        /// Products not loaded (yet): the About screen shows no tip section,
        /// so the app degrades gracefully offline or before App Store Connect
        /// has the products.
        case unavailable
        case ready
        case purchasing
        case thanked
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var phase: Phase = .unavailable

    private var updatesTask: Task<Void, Never>?

    init() {
        // Finish stray transactions (e.g. app killed mid-purchase) —
        // consumables sit in the queue until finished.
        updatesTask = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
            if !products.isEmpty { phase = .ready }
        } catch {
            phase = .unavailable
        }
    }

    func tip(_ product: Product) async {
        guard phase == .ready || phase == .thanked else { return }
        phase = .purchasing
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                phase = .thanked
                return
            }
        } catch {
            // A failed or cancelled tip just goes back to the buttons.
        }
        phase = .ready
    }
}
