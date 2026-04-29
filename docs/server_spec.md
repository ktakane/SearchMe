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
| max_members | INTEGER | 最大人数（2/6/20/0=無制限） |
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

**リクエスト**
```json
{ "max_members": 20 }
```

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
