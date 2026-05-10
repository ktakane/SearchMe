import StoreKit
import SwiftUI
import Combine

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
        case .none:       return 2
        case .personal:   return 6
        case .team:       return 20
        case .enterprise: return Int.max
        }
    }

    var label: String {
        switch self {
        case .none:       return "無償版"
        case .personal:   return "家族"
        case .team:       return "グループ"
        case .enterprise: return "企業"
        }
    }

    var groupLabel: String {
        switch self {
        case .none, .personal: return "家族"
        case .team:            return "グループ"
        case .enterprise:      return "企業"
        }
    }

    static func from(serverString s: String) -> PlanType {
        switch s {
        case "personal":   return .personal
        case "team":       return .team
        case "enterprise": return .enterprise
        default:           return .none
        }
    }
}

// MARK: - SubscriptionManager
//
// 設計:
// - 機能ゲート判定の主は「サーバーが返すグループのサブスク状態」
// - StoreKit のローカル Transaction は「オーナーが購入した直後にサーバーへ JWS を登録する」用途のみ
// - オフライン対応: 最後のサーバー応答を UserDefaults にキャッシュ。最終取得から24h以内なら有効
// - 既存ユーザー自動マイグレーション: ローカルに有効な Transaction があってサーバーが未登録なら、自動で register を呼ぶ

@MainActor
final class SubscriptionManager: ObservableObject {

    @Published var isSubscribed: Bool = false
    @Published var planType: PlanType = .none
    @Published var products: [Product] = []
    @Published var errorMessage: String? = nil
    @Published var isPurchasing: Bool = false

    /// 現在ログイン中のグループのサブスク状態（最後にサーバーから取得した内容）
    @Published var groupSubscription: GroupSubscription?

    private var transactionListener: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private weak var appState: AppState?

    // UserDefaults キャッシュ
    private let cacheKey         = "groupSubscriptionCache"
    private let cacheFetchedAtKey = "groupSubscriptionCacheFetchedAt"
    private let cacheGroupIdKey   = "groupSubscriptionCacheGroupId"
    private let cacheTTL: TimeInterval = 60 * 60 * 24  // 24h

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
        Task { await loadProducts() }
    }

    deinit { transactionListener?.cancel() }

    /// AppState を関連付け、グループ変化を監視して自動的にサブスク状態を再取得する。
    /// SearchMeApp 側で `.onAppear` などから呼ぶ想定。
    func bind(appState: AppState) {
        self.appState = appState
        cancellables.removeAll()
        appState.$groupId
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refresh() }
            }
            .store(in: &cancellables)
    }

    // MARK: - 読み込み

    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
            await MainActor.run { self.products = fetched }
        } catch {
            await MainActor.run { self.errorMessage = "商品情報の取得に失敗しました" }
        }
    }

    /// グループ加入後・タブ切替時・購入後に呼ぶ。
    /// サーバーからグループのサブスク状態を取得し、未登録ならローカル Transaction で自動登録する。
    func refresh() async {
        guard let appState = appState, !appState.groupId.isEmpty else {
            // グループ未参加。ローカル StoreKit のみで暫定判定（オーナーが setup 前に購入した場合のフォールバック）
            await applyLocalOnly()
            return
        }

        // キャッシュを先に当てて UI を即時更新（オフラインや起動直後のため）
        applyCacheIfFresh(for: appState.groupId)

        // サーバーから最新を取得
        do {
            let sub = try await APIService.shared.fetchGroupSubscription(groupId: appState.groupId)
            await applyServer(sub, groupId: appState.groupId)

            // 既存ユーザー自動マイグレーション:
            // サーバー未登録 (.status == "none") かつローカルに有効 Transaction があり、自分がオーナーなら登録
            if !sub.isActive && appState.isOwner {
                await autoRegisterIfPossible(appState: appState)
            }
        } catch {
            // サーバーアクセス失敗。キャッシュがあればそれで継続、なければ無償版扱い
            if groupSubscription == nil { await applyLocalOnly() }
        }
    }

    /// グループ未参加時、または通信失敗時のフォールバック判定。
    /// ローカルの有効 Transaction がオーナーの個人購入を表している可能性があるため、ペイウォール表示判定には使う。
    /// ただしこの状態では機能ゲート（ダッシュボード等）は閉じる（= isSubscribed=false）。
    private func applyLocalOnly() async {
        await MainActor.run {
            self.isSubscribed = false
            self.planType = .none
            self.groupSubscription = nil
        }
    }

    private func applyServer(_ sub: GroupSubscription, groupId: String) async {
        await MainActor.run {
            self.groupSubscription = sub
            self.isSubscribed = sub.isActive
            self.planType = PlanType.from(serverString: sub.planType)
        }
        saveCache(sub, groupId: groupId)
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
                    await registerWithServer(jws: verification.jwsRepresentation)
                    await refresh()
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
            // 復元後、ローカルに active な Transaction があればサーバー登録（自動マイグレーションと同じ経路）
            if let appState = appState, appState.isOwner {
                await autoRegisterIfPossible(appState: appState)
            }
            await refresh()
        } catch {
            errorMessage = "購入の復元に失敗しました"
        }
    }

    // MARK: - サーバー登録

    /// 購入直後の JWS（VerificationResult.jwsRepresentation）をサーバーに送って登録する。
    private func registerWithServer(jws: String) async {
        guard let appState = appState, !appState.groupId.isEmpty, !appState.myMemberId.isEmpty else {
            errorMessage = "グループ未参加のため購入を反映できません"
            return
        }
        do {
            try await APIService.shared.registerSubscription(
                groupId: appState.groupId,
                ownerMemberId: appState.myMemberId,
                jwsRepresentation: jws
            )
        } catch {
            errorMessage = "サーバーへのサブスク登録に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 既存ユーザー自動マイグレーション: ローカルに有効な Transaction があれば JWS をサーバーに送る。
    private func autoRegisterIfPossible(appState: AppState) async {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            guard ProductID.all.contains(tx.productID) else { continue }
            do {
                try await APIService.shared.registerSubscription(
                    groupId: appState.groupId,
                    ownerMemberId: appState.myMemberId,
                    jwsRepresentation: result.jwsRepresentation
                )
                return  // 1件登録できれば十分
            } catch {
                // 409（他グループに紐付け済み）や401などはログだけ残す
                print("[Subscription] auto-register failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - バックグラウンドリスナー

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.registerWithServer(jws: result.jwsRepresentation)
                    await self?.refresh()
                }
            }
        }
    }

    // MARK: - キャッシュ

    private func saveCache(_ sub: GroupSubscription, groupId: String) {
        guard let data = try? JSONEncoder().encode(sub) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheFetchedAtKey)
        UserDefaults.standard.set(groupId, forKey: cacheGroupIdKey)
    }

    private func applyCacheIfFresh(for groupId: String) {
        guard let cachedGroupId = UserDefaults.standard.string(forKey: cacheGroupIdKey),
              cachedGroupId == groupId,
              let fetchedAt = UserDefaults.standard.object(forKey: cacheFetchedAtKey) as? Date,
              Date().timeIntervalSince(fetchedAt) < cacheTTL,
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let sub = try? JSONDecoder().decode(GroupSubscription.self, from: data)
        else { return }
        self.groupSubscription = sub
        self.isSubscribed = sub.isActive
        self.planType = PlanType.from(serverString: sub.planType)
    }

    // MARK: - 商品取得ヘルパー

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }
}
