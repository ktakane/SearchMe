# SearchMe 修正履歴

---

## 2026-05-10

### iOS アプリ（Phase 2: サーバー駆動ゲート判定）

| 日付 | ファイル | 変更内容 |
|------|---------|---------|
| 2026-05-10 | `Models/Models.swift` | `GroupSubscription` 構造体を追加（サーバーから取得するグループサブスク状態） |
| 2026-05-10 | `Services/APIService.swift` | `registerSubscription(groupId:ownerMemberId:jwsRepresentation:)` を追加 |
| 2026-05-10 | `Services/APIService.swift` | `fetchGroupSubscription(groupId:)` を追加 |
| 2026-05-10 | `Services/SubscriptionManager.swift` | サーバー応答を主としたゲート判定にリファクタ（`isSubscribed` `planType` の出所を `GET /api/groups/<id>/subscription` の応答に変更） |
| 2026-05-10 | `Services/SubscriptionManager.swift` | 購入成功時に `Transaction.jwsRepresentation` をサーバーに送る `registerWithServer` を追加 |
| 2026-05-10 | `Services/SubscriptionManager.swift` | 既存ユーザー自動マイグレーション `autoRegisterIfPossible` を追加（refresh時にサーバー未登録 + ローカル active なら登録） |
| 2026-05-10 | `Services/SubscriptionManager.swift` | `bind(appState:)` で Combine により groupId 変化を監視し、自動的に refresh を呼ぶ |
| 2026-05-10 | `Services/SubscriptionManager.swift` | UserDefaults キャッシュ（24h TTL）でオフライン時もサブスク状態を保持 |
| 2026-05-10 | `Services/SubscriptionManager.swift` | `PlanType.from(serverString:)` を追加（"personal"/"team"/"enterprise" → enum 変換） |
| 2026-05-10 | `SearchMeApp.swift` | 起動時に `subManager.bind(appState:)` を呼ぶよう追加 |

---

## 2026-05-09

### サーバー（Phase 1: オーナー基準サブスク基盤）

| 日付 | ファイル | 変更内容 |
|------|---------|---------|
| 2026-05-09 | `server/app.py` | `migrate_db()` に `groups` テーブル追加カラム（`owner_member_id`、サブスク関連7カラム）と `original_transaction_id` のユニークインデックスを追加 |
| 2026-05-09 | `server/app.py` | `create_group()` で `owner_member_id` を保存するよう変更 |
| 2026-05-09 | `server/app.py` | 新エンドポイント `POST /api/subscription/register`（オーナー購入時の検証＋紐付け）を追加 |
| 2026-05-09 | `server/app.py` | 新エンドポイント `GET /api/groups/<id>/subscription`（クライアントゲート判定用）を追加 |
| 2026-05-09 | `server/app.py` | 新エンドポイント `POST /api/subscription/notifications`（Server Notifications V2 受信）を追加 |
| 2026-05-09 | `server/app.py` | バックグラウンドスレッド `poll_subscription_status()` を追加（1時間毎に App Store Server API で状態再検証） |
| 2026-05-09 | `server/app_store_api.py` | 新規作成。App Store Server API クライアント（JWT生成・JWSデコード・通知署名検証・状態取得・productId→プラン導出） |

### App Store Connect / VPS で必要な追加作業

- App Store Connect → ユーザーとアクセス → キー → アプリ内課金 で API キーを発行（Issuer ID / Key ID / `.p8`）
- VPS の `/home/skyscanning/searchme_server/app_store_api_key.p8` に配置（パーミッション 600）
- 環境変数 `APP_STORE_ISSUER_ID` `APP_STORE_KEY_ID` を systemd unit に追記
- App Store Connect → App Information → App Store Server Notifications でV2の URL を `https://searchme.skyscanning.jp/api/subscription/notifications` に設定（Production / Sandbox 両方）

---

## 2026-05-05

### iOS アプリ（SearchMe）

| 日付 | ファイル | 変更内容 |
|------|---------|---------|
| 2026-05-05 | `SubscriptionManager.swift` | `PlanType.none` の `maxMembers` を 0 → 2 に変更（無償プランでオーナー+1名を許可） |
| 2026-05-05 | `SubscriptionManager.swift` | `PlanType.personal` の `label` を「個人・家族」→「家族」に変更 |
| 2026-05-05 | `SubscriptionManager.swift` | `PlanType.team` の `label` および `groupLabel` を「チーム」→「グループ」に変更 |
| 2026-05-05 | `PaywallView.swift` | 企業プランカードを非表示化（コードはコメントアウトで保持） |
| 2026-05-05 | `PaywallView.swift` | プラン表示名を「個人・家族」→「家族プラン」、「チーム」→「グループプラン」に変更 |
| 2026-05-05 | `PaywallView.swift` | `PlanCard` に `trialText: String?` パラメータ追加・「初月無料」バッジ表示対応 |
| 2026-05-05 | `PaywallView.swift` | `planCards` でStoreKit introductoryOfferを検出し無料トライアル有無を自動判定 |

### App Store Connect での追加作業が必要

- 家族プランの価格設定：月額600円 / 年額6000円
- グループプランの価格設定：月額2000円 / 年額20000円
- 企業プランをdeactivate
- 各有償プランにIntroductory Offer（Free Trial・1ヶ月）を設定

---

## 今後の作業時の注意

1. 修正前にバックアップを作成
2. 修正内容をこのファイルに追記
3. 修正後はGitHub pushすること（ktakane）
