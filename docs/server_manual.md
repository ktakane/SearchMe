# SearchMe サーバー運用マニュアル

## サーバー接続情報

| 項目 | 内容 |
|---|---|
| IPアドレス | 203.183.10.123 |
| ユーザー | skyscanning |
| SSH鍵 | ~/.ssh/inspection_vps |
| アプリディレクトリ | /home/skyscanning/searchme_server/ |
| DBファイル | /home/skyscanning/searchme_server/searchme.db |

**SSH接続コマンド**
```bash
ssh -i ~/.ssh/inspection_vps skyscanning@203.183.10.123
```

---

## プロセス管理

### gunicornの状態確認
```bash
ps aux | grep gunicorn | grep searchme
```

### gunicornの再起動（設定反映）
コードを変更した後はHUPシグナルでworkerを再起動する。
```bash
kill -HUP <マスターPID>
```
マスターPIDの確認:
```bash
ps aux | grep gunicorn | grep searchme | grep Ssl
```

### サーバーの動作確認
```bash
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5004/admin
```
`200` が返れば正常。

---

## コードの更新手順

1. ローカルで編集・GitHubにプッシュ
2. VPSにSSH接続
3. コードを取得
```bash
cd /home/skyscanning/searchme_server
git pull origin master
```
4. gunicornを再起動
```bash
kill -HUP <マスターPID>
```

---

## データベース操作

### 管理画面で確認
ブラウザで以下にアクセス:
```
https://searchme.skyscanning.jp/admin
```

### SQLiteに直接接続
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/home/skyscanning/searchme_server/searchme.db')
conn.row_factory = sqlite3.Row
# ここにSQL操作を記述
conn.close()
"
```

### データの全削除（テスト後のクリーン）
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/home/skyscanning/searchme_server/searchme.db')
cur = conn.cursor()
cur.execute('DELETE FROM location_history')
cur.execute('DELETE FROM device_tokens')
cur.execute('DELETE FROM members')
cur.execute('DELETE FROM groups')
conn.commit()
print('全データを削除しました')
conn.close()
"
```

### 移動履歴のみ削除
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/home/skyscanning/searchme_server/searchme.db')
conn.execute('DELETE FROM location_history')
conn.commit()
conn.close()
print('完了')
"
```

---

## APNs設定

| 項目 | 内容 |
|---|---|
| 環境 | production |
| Key ID | 72C8UG337B |
| Team ID | 5N3593DK92 |
| 鍵ファイル | /home/skyscanning/searchme_server/apns_key.p8 |
| ホスト | https://api.push.apple.com |

APNs鍵ファイルの更新が必要な場合はApple Developer Consoleから再ダウンロードし、同パスに配置する。

---

## 避難所データの更新

避難所データは `shelters` テーブルに格納されている。更新が必要な場合は国土交通省等のオープンデータを取り込む。

```bash
# バージョン確認
curl https://searchme.skyscanning.jp/api/shelters/version
```

---

## ログ確認

gunicornのログはsystemdのジャーナルまたはプロセスの標準出力で確認する。
```bash
# nohupで起動している場合
tail -f /tmp/searchme.log
```

---

## 定期メンテナンス

| 作業 | タイミング | 方法 |
|---|---|---|
| 移動履歴の古いデータ削除 | 自動（起動時） | cleanup_old_history()が7日以前を削除 |
| 地震監視スレッド | 自動（起動時） | 60秒ごとに気象庁APIをポーリング |
| DBバックアップ | 月1回推奨 | DBファイルをrsyncでMacにコピー |

**DBバックアップコマンド（Mac側で実行）**
```bash
rsync -avz -e "ssh -i ~/.ssh/inspection_vps" \
  skyscanning@203.183.10.123:/home/skyscanning/searchme_server/searchme.db \
  ~/Desktop/searchme_backup_$(date +%Y%m%d).db
```

---

## トラブルシューティング

### APIが応答しない
1. gunicornプロセスの確認
2. ポート5004が使用中か確認: `ss -tlnp | grep 5004`
3. ログを確認して例外を特定
4. gunicornを再起動

### APNs通知が届かない
1. apns_key.p8ファイルの存在確認
2. Key IDが環境変数に設定されているか確認
3. APNs証明書の有効期限確認（Apple Developer Console）
4. デバイストークンが登録されているか管理画面で確認

### 地震通知が来ない
1. 気象庁APIへの接続確認: `curl https://www.jma.go.jp/bosai/quake/data/list.json`
2. sent_earthquakesテーブルで送信済みイベントを確認
3. gunicornのログで地震監視スレッドのエラーを確認
