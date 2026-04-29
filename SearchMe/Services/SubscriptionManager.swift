import StoreKit
import SwiftUI

// MARK: - 商品ID

enum ProductID {
    static let personalMonthly   = "com.skyscanning.searchme.personal.monthly"
    static let personalYearly    = "com.skyscanning.searchme.personal.yearly"
    static let teamMonthly       = "com.skyscanning.searchme.team.monthly"
    static let teamYearly        = "com.skyscanning.searchme.team.yearly"
    static let enterpriseMonthly = "com.skyscanning.searchme.enterprise.monthly"
    static let enterpriseYearly  = "com.skyscanning.searchme.enterprise.yearly"

    static let all = [
        personalMonthly, personalYearly,
        teamMonthly, teamYearly,
        enterpriseMonthly, enterpriseYearly
    ]

    static let monthly = [personalMonthly, teamMonthly, enterpriseMonthly]
    static let yearly  = [personalYearly,  teamYearly,  enterpriseYearly]
}

// MARK: - プランタイプ

enum PlanType: Equatable {
    case none, personal, team, enterprise

    var maxMembers: Int {
        switch self {
        case .none:       return 0
        case .personal:   return 6
        case .team:       return 20
        case .enterprise: return Int.max
        }
    }

    var label: String {
        switch self {
        case .none:       return "無償版"
        case .personal:   return "個人・家族"
        case .team:       return "チーム"
        case .enterprise: return "企業"
        }
    }

    var groupLabel: String {
        switch self {
        case .none, .personal: return "家族"
        case .team:            return "チーム"
        case .enterprise:      return "企業"
        }
    }
}

// MARK: - SubscriptionManager

final class SubscriptionManager: ObservableObject {

    @Published var isSubscribed: Bool = false
    @Published var planType: PlanType = .none
    @Published var products: [Product] = []
    @Published var errorMessage: String? = nil
    @Published var isPurchasing: Bool = false

    private var transactionListener: Task<Void, Never>?

    #if DEBUG
    static let debugForceSubscribed = false
    #endif

    init() {
        #if DEBUG
        if SubscriptionManager.debugForceSubscribed {
            isSubscribed = true
            planType = .personal
            return
        }
        #endif
        transactionListener = listenForTransactions()
        Task { await refresh() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - 読み込み・状態確認

    func refresh() async {
        await loadProducts()
        await checkSubscriptionStatus()
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "商品情報の取得に失敗しました"
        }
    }

    func checkSubscriptionStatus() async {
        var subscribed = false
        var plan = PlanType.none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            switch tx.productID {
            case ProductID.personalMonthly, ProductID.personalYearly:
                subscribed = true; plan = .personal
            case ProductID.teamMonthly, ProductID.teamYearly:
                subscribed = true; plan = .team
            case ProductID.enterpriseMonthly, ProductID.enterpriseYearly:
                subscribed = true; plan = .enterprise
            default: break
            }
        }
        isSubscribed = subscribed
        planType = plan
    }

    // MARK: - 購入

    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await checkSubscriptionStatus()
                } else {
                    errorMessage = "購入の検証に失敗しました"
                }
            case .pending, .userCancelled: break
            @unknown default: break
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 復元

    func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            errorMessage = "購入の復元に失敗しました"
        }
    }

    // MARK: - バックグラウンドリスナー

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await checkSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - 商品取得ヘルパー

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }
}
