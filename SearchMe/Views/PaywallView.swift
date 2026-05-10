import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subManager: SubscriptionManager

    var body: some View {
        if #available(iOS 17.0, *) {
            modernPaywall
        } else {
            legacyPaywall
        }
    }

    // MARK: - iOS 17+ SubscriptionStoreView（Apple推奨）

    @available(iOS 17.0, *)
    private var modernPaywall: some View {
        SubscriptionStoreView(productIDs: [
            ProductID.personalMonthly, ProductID.personalYearly,
            ProductID.teamMonthly,     ProductID.teamYearly
        ]) {
            marketingContent
        }
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStorePickerItemBackground(.thinMaterial)
        .storeButton(.visible, for: .restorePurchases, .cancellation)
        .subscriptionStorePolicyDestination(
            url: URL(string: "https://skyscanning.jp/privacy-policy/")!,
            for: .privacyPolicy
        )
        .subscriptionStorePolicyDestination(
            url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            for: .termsOfService
        )
        .onInAppPurchaseCompletion { _, result in
            if case .success(let purchaseResult) = result,
               case .success = purchaseResult {
                await subManager.refresh()
                dismiss()
            }
        }
    }

    // MARK: - マーケティングコンテンツ（iOS 17+ ヘッダー）

    private var marketingContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("プレミアム機能を解放")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                FeatureRow(icon: "building.2.fill", text: "全国12万件の避難所マップ")
                FeatureRow(icon: "map.fill",        text: "移動履歴の確認")
                FeatureRow(icon: "clock.fill",      text: "位置情報の長期保存")
                FeatureRow(icon: "chart.bar.fill",  text: "家族ダッシュボード")
            }
            .padding()
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top)
    }

    // MARK: - iOS 16 フォールバック（既存カスタムUI）

    private var legacyPaywall: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    legacyHeader
                    legacyBillingToggle
                    legacyPlanCards
                    legacyFooter
                    if let error = subManager.errorMessage {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("プレミアムプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    // -- Legacy: ヘッダー --

    @State private var isYearly = false

    private let legacyPlans: [(title: String, subtitle: String, icon: String, color: Color,
                                monthlyID: String, yearlyID: String)] = [
        ("家族プラン",   "オーナー＋5名まで",  "person.2.fill", .orange,
         ProductID.personalMonthly, ProductID.personalYearly),
        ("グループプラン", "オーナー＋19名まで", "person.3.fill", .blue,
         ProductID.teamMonthly,     ProductID.teamYearly),
    ]

    private var legacyHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("プレミアム機能を解放")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                FeatureRow(icon: "building.2.fill", text: "全国12万件の避難所マップ")
                FeatureRow(icon: "map.fill",        text: "移動履歴の確認")
                FeatureRow(icon: "clock.fill",      text: "位置情報の長期保存")
                FeatureRow(icon: "chart.bar.fill",  text: "家族ダッシュボード")
            }
            .padding()
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // -- Legacy: 月額/年額トグル --

    private var legacyBillingToggle: some View {
        HStack(spacing: 0) {
            legacyToggleTab(label: "月額", selected: !isYearly) { isYearly = false }
            legacyToggleTab(label: "年額（お得）", selected: isYearly) { isYearly = true }
        }
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func legacyToggleTab(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? .white : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(selected ? .primary : .secondary)
                .shadow(color: selected ? .black.opacity(0.1) : .clear, radius: 2)
        }
        .padding(3)
    }

    // -- Legacy: プランカード --

    private var legacyPlanCards: some View {
        VStack(spacing: 16) {
            ForEach(legacyPlans, id: \.title) { plan in
                let productID = isYearly ? plan.yearlyID : plan.monthlyID
                let product   = subManager.product(for: productID)
                let hasTrial  = product?.subscription?.introductoryOffer?.paymentMode == .freeTrial
                PlanCard(
                    title:     plan.title,
                    subtitle:  plan.subtitle,
                    icon:      plan.icon,
                    color:     plan.color,
                    priceText: product?.displayPrice ?? "---",
                    period:    isYearly ? "/ 1年（自動更新）" : "/ 1ヶ月（自動更新）",
                    trialText: hasTrial ? "初月無料" : nil,
                    isLoading: subManager.isPurchasing,
                    onTap: {
                        guard let p = product else { return }
                        Task { await subManager.purchase(p) }
                    }
                )
            }
        }
    }

    // -- Legacy: フッター --

    private var legacyFooter: some View {
        VStack(spacing: 12) {
            Text(isYearly
                 ? "プランは1年ごとに自動更新されます。次の更新日の24時間前までにキャンセルしない限り、自動的に課金されます。"
                 : "プランは1ヶ月ごとに自動更新されます。次の更新日の24時間前までにキャンセルしない限り、自動的に課金されます。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await subManager.restore() }
            } label: {
                Text("購入を復元する")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Link("利用規約",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("・").foregroundColor(.secondary)
                Link("プライバシーポリシー",
                     destination: URL(string: "https://skyscanning.jp/privacy-policy/")!)
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
    }
}

// MARK: - サブビュー

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.orange).frame(width: 20)
            Text(text).font(.subheadline)
        }
    }
}

struct PlanCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let priceText: String
    let period: String
    let trialText: String?
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 48, height: 48)
                    Image(systemName: icon).foregroundColor(color).font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if let trial = trialText {
                            Text(trial)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: Capsule())
                                .foregroundColor(.green)
                        }
                    }
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(priceText).font(.headline).foregroundColor(color)
                        Text(period).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
