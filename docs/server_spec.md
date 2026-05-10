# SearchMe サーバー仕様書

## 概要

| 項目 | 内容 |
|---|---|
| サーバーOS | Ubuntu（VPS） |
| フレームワーク | Python / Flask |
| WSGIサーバー | gunicorn（ワーカー数: 2） |
| データベース | SQLite3 |
| ポート | 5004（nginxリバースプロキシ経由） |
| URL | https://searchme.skyscanning.jp |

---

## データベース設計

### groups テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | TEXT (PK) | UUID |
| name | TEXT | グループ名 |
| invite_code | TEXT (UNIQUE) | 招待コード（英大文字+数字6桁） |
| created_at | TEXT | 作成日時（ISO8601 JST） |
| max_members | INTEGER | 最大人数（2=無償版 / 6=家族プラン / 20=グループプラン）。サブスク登録時に productId から自動導出 |
| owner_member_id | TEXT | グループオーナーのメンバーID（作成者）。サブスク権利者と一致 |
| original_transaction_id | TEXT (UNIQUE) | Apple `originalTransactionId`。1 Apple ID = 1 オーナーグループ制約のためユニーク |
| subscription_product_id | TEXT | 購入商品ID（例: `com.skyscanning.searchme.personal.monthly`） |
| subscription_status | TEXT | `active` / `expired` / `revoked` / `in_grace` / `in_billing_retry` / `none` |
| subscription_expires_at | TEXT | 現在の請求期間の終了日時（ISO8601 JST） |
| subscription_last_verified_at | TEXT | Apple サーバーで最後に検証した日時 |
| subscription_environment | TEXT | `Production` / `Sandbox` |
| owner_member_id | TEXT | オーナーのメンバーID |

### members テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | TEXT (PK) | UUID |
| group_id | TEXT | グループID |
| name | TEXT | 表示名 |
| latitude | REAL | 緯度（災害モード中のみ） |
| longitude | REAL | 経度（災害モード中のみ） |
| battery | REAL | バッテリー残量（0.0〜1.0） |
| updated_at | TEXT | 最終位置更新日時 |
| safety_status | TEXT | 安否状態（safe / need_help） |
| safety_updated_at | TEXT | 安否更新日時 |
| battery_alerted | TEXT | アラート済みしきい値（カンマ区切り） |

### device_tokens テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | INTEGER (PK) | 自動採番 |
| member_id | TEXT (UNIQUE) | メンバーID |
| group_id | TEXT | グループID |
| token | TEXT | APNsデバイストークン |
| updated_at | TEXT | 更新日時 |

### location_history テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | INTEGER (PK) | 自動採番 |
| member_id | TEXT | メンバーID |
| group_id | TEXT | グループID |
| latitude | REAL | 緯度 |
| longitude | REAL | 経度 |
| battery | REAL | バッテリー残量 |
| recorded_at | TEXT | 記録日時 |

保持期間: 7日間（起動時に自動削除）

### disaster_events テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | TEXT (PK) | UUID |
| group_id | TEXT | グループID |
| activated_at | TEXT | 開始日時 |
| deactivated_at | TEXT | 終了日時 |
| is_active | INTEGER | 稼働中フラグ（1=稼働中） |

### shelters テーブル

| カラム | 型 | 説明 |
|---|---|---|
| id | INTEGER (PK) | 避難所ID |
| name | TEXT | 避難所名 |
| address | TEXT | 住所 |
| latitude | REAL | 緯度 |
| longitude | REAL | 経度 |
| earthquake | INTEGER | 地震対応（1=対応） |
| tsunami | INTEGER | 津波対応 |
| flood | INTEGER | 洪水対応 |
| landslide | INTEGER | 土砂対応 |
| storm_surge | INTEGER | 高潮対応 |
| fire | INTEGER | 火災対応 |
| inland_flood | INTEGER | 内水対応 |
| volcano | INTEGER | 火山対応 |

---

## API エンドポイント一覧

### グループ管理

#### POST /api/groups
グループを新規作成する。

**リクエスト**
```json
{
  "name": "高根ファミリー",
  "owner_name": "くにお",
  "max_members": 6
}
```

**レスポンス**
```json
{
  "group": { "id": "uuid", "name": "高根ファミリー", "inviteCode": "ABC123" },
  "member": { "id": "uuid", "groupId": "uuid", "name": "くにお", "isMe": true },
  "isOwner": true
}
```

---

#### POST /api/groups/join
招待コードでグループに参加する。

**リクエスト**
```json
{
  "invite_code": "ABC123",
  "name": "花子"
}
```

**レスポンス**（成功時）
```json
{
  "group": { "id": "uuid", "name": "高根ファミリー", "inviteCode": "ABC123" },
  "member": { "id": "uuid", "groupId": "uuid", "name": "花子", "isMe": true },
  "isOwner": false
}
```

**エラー**
- `404`: 招待コード不正
- `403`: 人数上限（`{"error": "group is full", "max_members": 6}`）

---

#### GET /api/groups/{group_id}/members
グループメンバー一覧を取得する。

**レスポンス**
```json
[
  {
    "id": "uuid",
    "groupId": "uuid",
    "name": "くにお",
    "latitude": 35.6762,
    "longitude": 139.6503,
    "batteryLevel": 0.85,
    "updatedAt": "2026-04-30T10:00:00+09:00",
    "safetyStatus": "safe",
    "safetyUpdatedAt": "2026-04-30T10:00:00+09:00",
    "isMe": false
  }
]
```

**エラー**
- `404`: グループが存在しない（解散済み含む）

---

#### PUT /api/groups/{group_id}/plan
グループの最大人数を更新する（プラン変更時）。

> **互換性のために残置**。新クライアントは `/api/subscription/register` 経由でプランを更新する。サーバー側の Apple 検証を経ないため、運用ログで監視する。

**リクエスト**
```json
{ "max_members": 20 }
```

---

#### POST /api/subscription/register
オーナー購入直後にクライアントから JWS Transaction を受け取り、Apple サーバーで検証してグループに紐付ける。

**リクエスト**
```json
{
  "group_id": "...",
  "owner_member_id": "...",
  "jws_representation": "eyJhbGc..."
}
```

**処理**
1. JWS をデコードし `originalTransactionId` `productId` `environment` を取得
2. グループのオーナー一致を確認
3. `original_transaction_id` が他グループで使用中なら 409
4. App Store Server API で当該 transaction の状態を取得（active 必須）
5. グループにサブスク情報を保存。`max_members` は productId から自動導出

**レスポンス**
```json
{
  "ok": true,
  "planType": "personal",
  "maxMembers": 6,
  "subscriptionStatus": "active",
  "expiresAt": "2026-06-09T12:34:56+09:00"
}
```

**エラー**
- 400: パラメータ不足 / JWS 不正 / 未知の productId
- 401: Apple 側で active でない
- 403: オーナー不一致 or メンバーでない
- 404: グループが存在しない
- 409: `original_transaction_id` が他グループで使用中
- 502: Apple サーバーへの問い合わせ失敗

---

#### GET /api/groups/{group_id}/subscription
クライアントの機能ゲート判定用。グループの現在のサブスク状態を返す。アプリ起動時・タブ切替時に呼ばれる想定。

**レスポンス**
```json
{
  "isActive":      true,
  "planType":      "personal",
  "maxMembers":    6,
  "expiresAt":     "2026-06-09T12:34:56+09:00",
  "ownerMemberId": "...",
  "status":        "active"
}
```

`isActive=true` の場合、グループ全メンバーが有償機能（避難所マップ・移動履歴・ダッシュボード）を利用可能。`status` は `active` / `expired` / `revoked` / `in_grace` / `in_billing_retry` / `none`。

**エラー**
- 404: グループが存在しない

---

#### POST /api/subscription/notifications
App Store Server Notifications V2 受信用 Webhook。Apple から push される。

**リクエスト**（Apple から）
```json
{ "signedPayload": "<JWS>" }
```

**処理**
1. signedPayload を検証してデコード
2. `notificationType` に応じて DB の `subscription_status` を更新
   - `SUBSCRIBED` / `DID_RENEW` / `OFFER_REDEEMED` → `active`
   - `EXPIRED` / `GRACE_PERIOD_EXPIRED` → `expired`
   - `REVOKE` / `REFUND` → `revoked`（即時ロック）
   - `DID_FAIL_TO_RENEW` → `in_billing_retry`（subtype が `GRACE_PERIOD` なら `in_grace`）
3. 200 を返す（500 を返すと Apple が再送する）

**App Store Connect 設定**
- Production Server URL: `https://searchme.skyscanning.jp/api/subscription/notifications`
- Sandbox Server URL: 同上（環境はペイロード内 `environment` で判別）
- Version: V2

---

#### バックグラウンドポーリング
`poll_subscription_status()` が起動時にデーモンスレッドとして動き、1時間毎に `original_transaction_id` を持つ全グループに対して App Store Server API で状態を再検証する。Webhook の取りこぼしに備えた二重防御。

---

#### DELETE /api/groups/{group_id}
グループを解散する（オーナーのみ）。

**リクエスト**
```json
{ "member_id": "オーナーのメンバーID" }
```

**エラー**
- `403`: オーナー以外が操作しようとした場合
- `404`: グループが存在しない

---

#### DELETE /api/members/{member_id}
グループから退出する。

**エラー**
- `403`: オーナーは退出不可（`{"error": "owner_cannot_leave"}`）

---

### 位置情報

#### POST /api/location
現在位置を送信する（災害モード中に定期実行）。

**リクエスト**
```json
{
  "memberId": "uuid",
  "groupId": "uuid",
  "latitude": 35.6762,
  "longitude": 139.6503,
  "batteryLevel": 0.85,
  "timestamp": "2026-04-30T10:00:00+09:00"
}
```

バッテリーが20%/10%/5%を下回った場合、グループ内の他メンバーにAPNs通知を送信。

---

#### GET /api/members/{member_id}/history
移動履歴を取得する（最大7日間）。

**クエリパラメータ**
- `hours`: 取得期間（例: 24、最大168）

**レスポンス**
```json
[
  {
    "id": 1,
    "latitude": 35.6762,
    "longitude": 139.6503,
    "battery": 0.85,
    "recordedAt": "2026-04-30T10:00:00+09:00"
  }
]
```

---

### 安否確認

#### POST /api/safety
安否状態を報告する。グループ内の他メンバーにAPNs通知を送信。

**リクエスト**
```json
{
  "member_id": "uuid",
  "group_id": "uuid",
  "status": "safe"
}
```

`status`: `safe`（無事） / `need_help`（助けが必要）

---

### 災害モード

#### POST /api/disaster/activate
グループの災害モードを開始する。

**リクエスト**
```json
{ "group_id": "uuid" }
```

#### POST /api/disaster/deactivate
グループの災害モードを終了する。全メンバーの位置情報をクリアする。

---

### デバイストークン

#### POST /api/register-token
APNsデバイストークンを登録する。

**リクエスト**
```json
{
  "token": "apns_device_token",
  "member_id": "uuid",
  "group_id": "uuid"
}
```

---

### 避難所

#### GET /api/shelters/version
避難所データのバージョンを取得する。

#### GET /api/shelters/download
全避難所データをgzip圧縮JSONで取得する（iOSアプリが起動時にキャッシュ）。

#### GET /api/shelters/nearby
周辺の避難所を取得する。

**クエリパラメータ**
- `lat`: 緯度
- `lng`: 経度
- `radius`: 半径（メートル、デフォルト3000）

---

### 管理画面

#### GET /admin
グループ・メンバー・デバイストークンの一覧をHTML形式で表示する。

---

## APNs通知一覧

| イベント | タイトル | 本文 |
|---|---|---|
| 地震検知（震度5弱以上） | ⚠️ 災害検知 | 震度Xの地震が発生しました |
| 安否報告（無事） | 🔔 安否確認 | 〇〇さんが「無事です」と報告しました |
| 安否報告（要救助） | 🔔 安否確認 | 〇〇さんが「助けが必要」と報告しました |
| バッテリー低下（20/10/5%） | ⚡ バッテリー低下 | 〇〇さんのバッテリーが残りX%です |

---

## 地震監視

- 気象庁API（`https://www.jma.go.jp/bosai/quake/data/list.json`）を60秒間隔でポーリング
- 震度5弱（5-）以上を検知した場合、全デバイスにAPNs通知を送信
- 送信済みイベントは `sent_earthquakes` テーブルで管理（重複送信防止）
