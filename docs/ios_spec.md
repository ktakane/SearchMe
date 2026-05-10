# SearchMe iOS アプリ仕様書

## 概要

| 項目 | 内容 |
|---|---|
| Bundle ID | com.skyscanning.searchme |
| 最小OSバージョン | iOS 16.0 |
| 対応デバイス | iPhone（iPad非対応） |
| 向き | ポートレートのみ |
| 言語 | 日本語 |
| フレームワーク | SwiftUI、StoreKit 2、MapKit、CoreLocation |
| プロジェクト管理 | XcodeGen（project.yml） |
| リポジトリ | https://github.com/ktakane/SearchMe |

---

## 画面構成

### 初期設定画面（SetupView）
アプリ初回起動時またはグループ未所属時に表示される。

- **グループを作成する**: グループ名・自分の名前を入力してグループを作成
- **グループに参加する**: 招待コード・自分の名前を入力して既存グループに参加

グループ作成・参加後は `AppState` に情報を保存し、メインタブ画面へ遷移する。

---

### メインタブ（MainTabView）
4つのタブで構成される。

| タブ | 画面 | 説明 |
|---|---|---|
| ホーム | HomeView | 災害モードの開始・停止、安否報告 |
| マップ | MapView | 家族の位置をリアルタイム表示 |
| 家族/グループ | DashboardView（有償）/ FamilyListView（無償） | メンバー一覧・安否状況 |
| 設定 | SettingsView | グループ設定・退出・解散 |

タブのラベル（「家族」「グループ」）はプランに応じて変化する。

---

### ホーム画面（HomeView）

**ステータスカード**
- モード表示（通常モード / 災害モード稼働中）
- グループ名・招待コード
- 位置情報の認証状態（「常に許可」でない場合に警告表示）

**災害モードボタン**
- 通常時: 「災害モードを開始」（オレンジ大ボタン）
- 災害モード中: 「災害モードを停止」（赤大ボタン）
- 停止時は安否確認シートを表示し、安否報告後に停止する

**安否報告ボタン**（災害モード中のみ表示）
- 「安否を報告する」ボタンで安否確認シートを表示

**災害モード開始時の処理**
1. `AppState.isDisasterMode = true`
2. `LocationService.startDisasterTracking()` で位置情報の継続送信開始
3. 1時間後に安否確認リマインダー通知をスケジュール
4. サーバーに `POST /api/disaster/activate` を送信

**災害モード停止時の処理**
1. 安否報告を送信
2. `LocationService.stopDisasterTracking()` で位置情報送信停止
3. リマインダー通知をキャンセル
4. サーバーに `POST /api/disaster/deactivate` を送信

---

### マップ画面（MapView）

- グループメンバーの現在地をピンで表示
- 自分のピンは青、他メンバーはオレンジ
- ピンに名前・最終更新時刻を表示（白文字・半透明黒背景）
- 避難所表示ボタン（有償版のみ）: 現在地周辺3km以内の避難所をピン表示
- 更新ボタンで手動再読み込み
- 起動時は自動でメンバー位置を取得し地図を移動
- メンバーが位置情報未取得の場合はデバイスのGPS位置を表示
- グループ解散検知（サーバーから404）時は自動でグループ退出

**避難所ピンタップ**: 避難所詳細シートを表示
- 施設名・住所・対応災害種別
- 「マップで経路を見る」でApple Mapsへ遷移

---

### ダッシュボード画面（DashboardView）※有償版

- **安否進捗カード**（災害モード中のみ）: 回答率プログレスバー、無事/要救助/未回答の人数
- **サマリータイル**: 総メンバー数、位置確認中人数、低バッテリー人数
- **メンバーカード（2列グリッド）**: 名前・安否バッジ・バッテリー・最終更新
- メンバーカードタップで移動履歴画面へ遷移
- 30秒ごとに自動更新
- グループ解散検知時は自動退出

無償版ユーザーには `FamilyListView`（アップグレード促進バナー付き）を表示。

---

### 移動履歴画面（HistoryView）※有償版

- 期間選択: 6時間 / 24時間 / 3日間 / 7日間
- MKMapViewで移動ルートをオレンジのポリラインで表示
- 「開始」（緑）「現在地」（オレンジ）マーカー
- タイムライン一覧: 日時・座標・バッテリー残量

---

### 安否確認シート（SafetySheet）

- 「無事です」（緑ボタン）
- 「助けが必要」（赤ボタン）
- 報告後、次回リマインダー通知を1時間後にスケジュール
- 停止前安否確認の場合はリマインダーをスケジュールしない

---

### 設定画面（SettingsView）

- 自分の情報（名前・グループ名・招待コード・オーナーバッジ）
- 招待コードのコピー・共有
- **オーナーの場合**: 「グループを解散する」ボタン → 解散確認シートを表示
- **メンバーの場合**: 「グループから退出」ボタン → 確認アラートを表示

**グループ解散確認シート（DisbandConfirmSheet）**
- 解散による影響を4項目で説明
- 「グループを解散する」（赤）/ 「キャンセル」ボタン

---

### ペイウォール画面（PaywallView）

- 家族プラン / グループプランの2プランを表示
- 月額・年額の切り替えタブ
- 初月無料（Introductory Offer 適用時のみ「初月無料」バッジを動的表示）
- 購入・復元ボタン

> 旧「企業プラン」は廃止。`PlanType.enterprise` および関連 ProductID はソースコードに残るが、StoreKit/App Store Connect では非販売。

---

## サブスクリプション

| プラン | 最大人数 | 月額 | 年額 | 試用 |
|---|---|---|---|---|
| 無償版 | 2名（オーナー＋1名） | - | - | - |
| 家族プラン | 6名 | ¥600 | ¥6,000 | 初月無料 |
| グループプラン | 20名 | ¥2,000 | ¥20,000 | 初月無料 |

有償版の機能: 避難所マップ・移動履歴・ダッシュボード

**StoreKit商品ID**
- `com.skyscanning.searchme.personal.monthly` / `.personal.yearly`（家族プラン）
- `com.skyscanning.searchme.team.monthly` / `.team.yearly`（グループプラン）

> 旧「企業プラン」（`com.skyscanning.searchme.enterprise.*`）は廃止。`SubscriptionManager.swift` の `PlanType.enterprise` および `ProductID.enterprise*` 定義はコードに残るが、StoreKit構成ファイルからは削除済みで App Store では販売しない。

---

## 主要クラス・ファイル構成

### Services/
| ファイル | 役割 |
|---|---|
| AppState.swift | グループ情報・ユーザー情報の永続化（UserDefaults） |
| APIService.swift | サーバーAPIとの通信 |
| LocationService.swift | CoreLocationによる位置情報取得・送信 |
| SubscriptionManager.swift | StoreKit 2によるサブスクリプション管理 |
| ShelterService.swift | 避難所データのSQLiteキャッシュ管理 |

### Models/
| ファイル | 役割 |
|---|---|
| Models.swift | FamilyMember、FamilyGroup、Shelter、HistoryPoint等のデータモデル |

### Views/
| ファイル | 役割 |
|---|---|
| MainTabView.swift | タブナビゲーション |
| HomeView.swift | ホーム画面 |
| MapView.swift | マップ画面・MapViewModel |
| DashboardView.swift | ダッシュボード画面 |
| HistoryView.swift | 移動履歴画面 |
| SafetySheet.swift | 安否確認シート |
| SettingsView.swift | 設定画面・解散確認シート |
| SetupView.swift | 初期設定画面 |
| PaywallView.swift | ペイウォール画面 |
| FamilyListView.swift | 無償版メンバー一覧 |

---

## AppState の保持データ

| キー | 内容 |
|---|---|
| myMemberId | 自分のメンバーID |
| myName | 自分の表示名 |
| groupId | グループID |
| groupName | グループ名 |
| inviteCode | 招待コード |
| isOwner | グループオーナーかどうか |
| isDisasterMode | 災害モード稼働中かどうか |

---

## 位置情報の動作仕様

- 権限: 「常に許可」を推奨（バックグラウンド送信のため）
- 精度: kCLLocationAccuracyHundredMeters
- 距離フィルター: 50m
- **平常時**: 位置情報を取得するがサーバーへは送信しない
- **災害モード中**: 位置変化時にサーバーへ自動送信、有意な位置変化も監視

---

## プッシュ通知の受信処理

| type | 処理内容 |
|---|---|
| disaster_alert | 自動で災害モードを開始 |
| safety_report | ダッシュボード・一覧を更新 |
| battery_alert | バックグラウンドで受信（表示のみ） |
