from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import sqlite3
import random
import string
import os
import threading
import time
import json
import jwt
import httpx
import requests
from datetime import datetime, timedelta, timezone

import app_store_api

app = Flask(__name__)
CORS(app)

DB_PATH = os.path.join(os.path.dirname(__file__), 'searchme.db')
JST = timezone(timedelta(hours=9))

# APNs設定（環境変数から読み込み）
APNS_KEY_PATH  = os.environ.get('APNS_KEY_PATH', '/home/skyscanning/searchme_server/apns_key.p8')
APNS_KEY_ID    = os.environ.get('APNS_KEY_ID', '')
APNS_TEAM_ID   = os.environ.get('APNS_TEAM_ID', '5N3593DK92')
APNS_BUNDLE_ID = 'com.skyscanning.searchme'
APNS_HOST      = 'https://api.push.apple.com'

# 気象庁API
JMA_URL = 'https://www.jma.go.jp/bosai/quake/data/list.json'
TRIGGER_INTENSITY    = ['5-', '5+', '6-', '6+', '7']
BATTERY_THRESHOLDS   = [20, 10, 5]

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def migrate_db():
    with get_db() as conn:
        for col in ('safety_status', 'safety_updated_at', 'battery_alerted'):
            try:
                conn.execute(f'ALTER TABLE members ADD COLUMN {col} TEXT')
            except Exception:
                pass
        try:
            conn.execute('ALTER TABLE groups ADD COLUMN max_members INTEGER NOT NULL DEFAULT 2')
        except Exception:
            pass
        for col_def in (
            'owner_member_id TEXT',
            'original_transaction_id TEXT',
            'subscription_product_id TEXT',
            'subscription_status TEXT',
            'subscription_expires_at TEXT',
            'subscription_last_verified_at TEXT',
            'subscription_environment TEXT',
        ):
            try:
                conn.execute(f'ALTER TABLE groups ADD COLUMN {col_def}')
            except Exception:
                pass
        try:
            conn.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_orig_tx '
                'ON groups (original_transaction_id) '
                'WHERE original_transaction_id IS NOT NULL'
            )
        except Exception:
            pass
        conn.executescript('''
            CREATE TABLE IF NOT EXISTS location_history (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                member_id   TEXT NOT NULL,
                group_id    TEXT NOT NULL,
                latitude    REAL NOT NULL,
                longitude   REAL NOT NULL,
                battery     REAL,
                recorded_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_history_member
                ON location_history (member_id, recorded_at);
        ''')

def init_db():
    with get_db() as conn:
        conn.executescript('''
            CREATE TABLE IF NOT EXISTS groups (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                invite_code TEXT UNIQUE NOT NULL,
                created_at  TEXT NOT NULL,
                max_members INTEGER NOT NULL DEFAULT 2
            );
            CREATE TABLE IF NOT EXISTS members (
                id          TEXT PRIMARY KEY,
                group_id    TEXT NOT NULL,
                name        TEXT NOT NULL,
                latitude    REAL,
                longitude   REAL,
                battery     REAL,
                updated_at  TEXT,
                FOREIGN KEY (group_id) REFERENCES groups(id)
            );
            CREATE TABLE IF NOT EXISTS device_tokens (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                member_id  TEXT NOT NULL,
                group_id   TEXT NOT NULL,
                token      TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(member_id)
            );
            CREATE TABLE IF NOT EXISTS disaster_events (
                id             TEXT PRIMARY KEY,
                group_id       TEXT NOT NULL,
                activated_at   TEXT NOT NULL,
                deactivated_at TEXT,
                is_active      INTEGER DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS sent_earthquakes (
                event_id   TEXT PRIMARY KEY,
                sent_at    TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS shelters (
                id           INTEGER PRIMARY KEY,
                name         TEXT NOT NULL,
                address      TEXT,
                latitude     REAL NOT NULL,
                longitude    REAL NOT NULL,
                flood        INTEGER DEFAULT 0,
                landslide    INTEGER DEFAULT 0,
                storm_surge  INTEGER DEFAULT 0,
                earthquake   INTEGER DEFAULT 0,
                tsunami      INTEGER DEFAULT 0,
                fire         INTEGER DEFAULT 0,
                inland_flood INTEGER DEFAULT 0,
                volcano      INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_shelters_lat ON shelters (latitude);
            CREATE INDEX IF NOT EXISTS idx_shelters_lng ON shelters (longitude);
            CREATE TABLE IF NOT EXISTS shelter_meta (
                key   TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE IF NOT EXISTS location_history (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                member_id   TEXT NOT NULL,
                group_id    TEXT NOT NULL,
                latitude    REAL NOT NULL,
                longitude   REAL NOT NULL,
                battery     REAL,
                recorded_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_history_member
                ON location_history (member_id, recorded_at);
        ''')

def generate_invite_code():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

def generate_id():
    import uuid
    return str(uuid.uuid4())

def now_iso():
    return datetime.now(JST).isoformat()

# MARK: - APNs送信

def send_apns(device_token: str, payload: dict):
    try:
        if not os.path.exists(APNS_KEY_PATH) or not APNS_KEY_ID:
            print('[APNs] キーファイルまたはKey IDが未設定')
            return False

        with open(APNS_KEY_PATH, 'r') as f:
            private_key = f.read()

        token = jwt.encode(
            {'iss': APNS_TEAM_ID, 'iat': time.time()},
            private_key,
            algorithm='ES256',
            headers={'kid': APNS_KEY_ID}
        )

        headers = {
            'authorization': f'bearer {token}',
            'apns-topic': APNS_BUNDLE_ID,
            'apns-push-type': 'background',
            'apns-priority': '5',
        }

        url = f'{APNS_HOST}/3/device/{device_token}'
        with httpx.Client(http2=True) as client:
            resp = client.post(url, json=payload, headers=headers, timeout=10)
            return resp.status_code == 200

    except Exception as e:
        print(f'[APNs] 送信エラー: {e}')
        return False

def notify_all_disaster(reason: str, affected_areas: list):
    # affected_areas が空の場合は全員に送信（初期速報など地域データ未確定時）
    payload = {
        'aps': {
            'content-available': 1,
            'sound': 'default',
            'alert': {'title': '⚠️ 災害検知', 'body': reason}
        },
        'type': 'disaster_alert',
        'reason': reason,
        'affected_areas': affected_areas
    }
    with get_db() as conn:
        tokens = conn.execute('SELECT token FROM device_tokens').fetchall()
    for row in tokens:
        send_apns(row['token'], payload)
    print(f'[通知] {len(tokens)}件送信: {reason}')

# MARK: - 気象庁APIポーリング

def poll_earthquake():
    print('[地震監視] 開始')
    while True:
        try:
            resp = requests.get(JMA_URL, timeout=10)
            if resp.status_code == 200:
                quakes = resp.json()
                with get_db() as conn:
                    for q in quakes[:10]:
                        event_id = q.get('id', '')
                        intensity = q.get('maxi', '')
                        if not event_id or intensity not in TRIGGER_INTENSITY:
                            continue
                        already_sent = conn.execute(
                            'SELECT 1 FROM sent_earthquakes WHERE event_id = ?', (event_id,)
                        ).fetchone()
                        if already_sent:
                            continue
                        conn.execute(
                            'INSERT INTO sent_earthquakes (event_id, sent_at) VALUES (?, ?)',
                            (event_id, now_iso())
                        )
                        title = q.get('en_anm', q.get('anm', '地震'))
                        reason = f'震度{intensity}の地震が発生しました（{title}）'
                        affected_areas = [
                            {'code': area['code'], 'maxi': area['maxi']}
                            for area in q.get('int', [])
                            if area.get('maxi') in TRIGGER_INTENSITY
                        ]
                        threading.Thread(target=notify_all_disaster, args=(reason, affected_areas), daemon=True).start()
        except Exception as e:
            print(f'[地震監視] エラー: {e}')
        time.sleep(60)

# MARK: - グループ

VALID_MAX_MEMBERS = {2, 6, 20, 0}  # 0 = unlimited

@app.route('/api/groups', methods=['POST'])
def create_group():
    data        = request.get_json()
    name        = data.get('name', '').strip()
    owner_name  = data.get('owner_name', '').strip()
    max_members = int(data.get('max_members', 2))
    if not name or not owner_name:
        return jsonify({'error': 'name and owner_name are required'}), 400
    if max_members not in VALID_MAX_MEMBERS:
        max_members = 2

    group_id    = generate_id()
    member_id   = generate_id()
    invite_code = generate_invite_code()
    with get_db() as conn:
        conn.execute(
            'INSERT INTO groups (id, name, invite_code, created_at, max_members, owner_member_id) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            (group_id, name, invite_code, now_iso(), max_members, member_id)
        )
        conn.execute(
            'INSERT INTO members (id, group_id, name) VALUES (?, ?, ?)',
            (member_id, group_id, owner_name)
        )
    return jsonify({
        'group':  {'id': group_id, 'name': name, 'inviteCode': invite_code},
        'member': {'id': member_id, 'groupId': group_id, 'name': owner_name, 'isMe': True}
    })

@app.route('/api/groups/join', methods=['POST'])
def join_group():
    data        = request.get_json()
    invite_code = data.get('invite_code', '').strip().upper()
    member_name = data.get('name', '').strip()
    if not invite_code or not member_name:
        return jsonify({'error': 'invite_code and name are required'}), 400

    with get_db() as conn:
        group = conn.execute(
            'SELECT * FROM groups WHERE invite_code = ?', (invite_code,)
        ).fetchone()
        if not group:
            return jsonify({'error': 'invalid invite code'}), 404

        max_members = group['max_members']
        if max_members > 0:
            current_count = conn.execute(
                'SELECT COUNT(*) as cnt FROM members WHERE group_id = ?', (group['id'],)
            ).fetchone()['cnt']
            if current_count >= max_members:
                return jsonify({'error': 'group is full', 'max_members': max_members}), 403

        member_id = generate_id()
        conn.execute(
            'INSERT INTO members (id, group_id, name) VALUES (?, ?, ?)',
            (member_id, group['id'], member_name)
        )
    return jsonify({
        'group':  {'id': group['id'], 'name': group['name'], 'inviteCode': group['invite_code']},
        'member': {'id': member_id, 'groupId': group['id'], 'name': member_name, 'isMe': True}
    })

@app.route('/api/groups/<group_id>/plan', methods=['PUT'])
def update_group_plan(group_id):
    # 互換のため残す。新クライアントは /api/subscription/register 経由で max_members を更新する。
    data        = request.get_json()
    max_members = int(data.get('max_members', 2))
    if max_members not in VALID_MAX_MEMBERS:
        max_members = 2
    with get_db() as conn:
        conn.execute('UPDATE groups SET max_members = ? WHERE id = ?', (max_members, group_id))
    return jsonify({'ok': True})

# MARK: - サブスクリプション

def _expires_iso(expires_date_ms):
    if not expires_date_ms:
        return None
    return datetime.fromtimestamp(int(expires_date_ms) / 1000, tz=JST).isoformat()


def _is_active_status(status_label: str) -> bool:
    return status_label in ('active', 'in_grace', 'in_billing_retry')


@app.route('/api/subscription/register', methods=['POST'])
def register_subscription():
    """オーナー購入直後にクライアントから JWS Transaction を受け取り、
    Apple サーバーで検証してグループに紐付ける。
    """
    data = request.get_json() or {}
    group_id          = data.get('group_id', '').strip()
    owner_member_id   = data.get('owner_member_id', '').strip()
    jws_representation = data.get('jws_representation', '').strip()

    if not group_id or not owner_member_id or not jws_representation:
        return jsonify({'error': 'group_id, owner_member_id, jws_representation are required'}), 400

    # JWS をデコードして originalTransactionId / productId / environment を取り出す
    try:
        tx = app_store_api.decode_jws(jws_representation)
    except Exception as e:
        return jsonify({'error': f'invalid jws: {e}'}), 400

    original_tx_id = tx.get('originalTransactionId')
    product_id     = tx.get('productId')
    environment    = tx.get('environment', 'Production')
    if not original_tx_id or not product_id:
        return jsonify({'error': 'jws missing originalTransactionId or productId'}), 400

    plan = app_store_api.plan_from_product(product_id)
    if not plan:
        return jsonify({'error': f'unknown product_id: {product_id}'}), 400
    plan_type, max_members = plan

    with get_db() as conn:
        group = conn.execute('SELECT * FROM groups WHERE id = ?', (group_id,)).fetchone()
        if not group:
            return jsonify({'error': 'group not found'}), 404

        # オーナー検証: 既知のオーナーがいる場合は一致を要求、未設定なら今回のmemberで上書き
        existing_owner = group['owner_member_id'] if 'owner_member_id' in group.keys() else None
        if existing_owner and existing_owner != owner_member_id:
            return jsonify({'error': 'requestor is not the group owner'}), 403

        member = conn.execute(
            'SELECT 1 FROM members WHERE id = ? AND group_id = ?',
            (owner_member_id, group_id)
        ).fetchone()
        if not member:
            return jsonify({'error': 'owner_member_id is not a member of the group'}), 403

        # 1 Apple ID = 1 オーナーグループ制約
        existing = conn.execute(
            'SELECT id FROM groups WHERE original_transaction_id = ? AND id != ?',
            (original_tx_id, group_id)
        ).fetchone()
        if existing:
            return jsonify({
                'error': 'this subscription is already linked to another group',
                'conflicting_group_id': existing['id']
            }), 409

    # Apple サーバーで現在の状態を確認
    status = app_store_api.get_subscription_status(original_tx_id, environment=environment)
    if not status:
        return jsonify({'error': 'failed to verify with App Store'}), 502

    status_label = app_store_api.status_label(status['status'])
    if not _is_active_status(status_label):
        return jsonify({'error': f'subscription is not active: {status_label}'}), 401

    expires_at = _expires_iso(status.get('expires_date_ms'))

    with get_db() as conn:
        conn.execute('''
            UPDATE groups
            SET owner_member_id = ?,
                original_transaction_id = ?,
                subscription_product_id = ?,
                subscription_status = ?,
                subscription_expires_at = ?,
                subscription_last_verified_at = ?,
                subscription_environment = ?,
                max_members = ?
            WHERE id = ?
        ''', (
            owner_member_id, original_tx_id, product_id,
            status_label, expires_at, now_iso(), environment,
            max_members, group_id
        ))

    return jsonify({
        'ok': True,
        'planType': plan_type,
        'maxMembers': max_members,
        'subscriptionStatus': status_label,
        'expiresAt': expires_at,
    })


@app.route('/api/groups/<group_id>/subscription', methods=['GET'])
def get_group_subscription(group_id):
    """クライアントの機能ゲート判定用。グループの現在のサブスク状態を返す。"""
    with get_db() as conn:
        group = conn.execute('SELECT * FROM groups WHERE id = ?', (group_id,)).fetchone()
    if not group:
        return jsonify({'error': 'group not found'}), 404

    keys = group.keys()
    status_label = group['subscription_status'] if 'subscription_status' in keys else None
    product_id   = group['subscription_product_id'] if 'subscription_product_id' in keys else None
    expires_at   = group['subscription_expires_at'] if 'subscription_expires_at' in keys else None
    owner_id     = group['owner_member_id'] if 'owner_member_id' in keys else None

    plan_type = 'none'
    if product_id:
        plan = app_store_api.plan_from_product(product_id)
        if plan:
            plan_type = plan[0]

    is_active = _is_active_status(status_label or '')

    return jsonify({
        'isActive':      is_active,
        'planType':      plan_type if is_active else 'none',
        'maxMembers':    group['max_members'],
        'expiresAt':     expires_at,
        'ownerMemberId': owner_id,
        'status':        status_label or 'none',
    })


@app.route('/api/subscription/notifications', methods=['POST'])
def subscription_notifications():
    """App Store Server Notifications V2 受信用 Webhook。"""
    data = request.get_json(silent=True) or {}
    signed_payload = data.get('signedPayload')
    if not signed_payload:
        return jsonify({'error': 'signedPayload required'}), 400

    try:
        notification = app_store_api.verify_notification(signed_payload)
    except Exception as e:
        print(f'[Notifications] verify failed: {e}')
        return jsonify({'error': 'invalid payload'}), 400

    notification_type = notification.get('notificationType')
    subtype           = notification.get('subtype')
    notif_data        = notification.get('data', {})
    signed_tx         = notif_data.get('signedTransactionInfo')
    environment       = notif_data.get('environment', 'Production')

    tx = {}
    if signed_tx:
        try:
            tx = app_store_api.decode_jws(signed_tx)
        except Exception as e:
            print(f'[Notifications] decode_jws failed: {e}')

    original_tx_id = tx.get('originalTransactionId')
    product_id     = tx.get('productId')
    expires_ms     = tx.get('expiresDate')

    if not original_tx_id:
        # 状態更新できないが200で返す（Appleの再送を止める）
        print(f'[Notifications] {notification_type}/{subtype}: no originalTransactionId')
        return jsonify({'ok': True})

    # 通知タイプから内部ステータスを決定
    new_status = None
    if notification_type in ('SUBSCRIBED', 'DID_RENEW', 'OFFER_REDEEMED'):
        new_status = 'active'
    elif notification_type == 'EXPIRED':
        new_status = 'expired'
    elif notification_type in ('REVOKE', 'REFUND'):
        new_status = 'revoked'
    elif notification_type == 'GRACE_PERIOD_EXPIRED':
        new_status = 'expired'
    elif notification_type == 'DID_FAIL_TO_RENEW':
        new_status = 'in_billing_retry' if subtype != 'GRACE_PERIOD' else 'in_grace'
    elif notification_type == 'DID_CHANGE_RENEWAL_STATUS':
        # 自動更新ON/OFF切替。状態は変えず最終検証時刻だけ更新
        pass

    expires_at = _expires_iso(expires_ms)

    with get_db() as conn:
        if new_status:
            conn.execute('''
                UPDATE groups
                SET subscription_status = ?,
                    subscription_expires_at = ?,
                    subscription_last_verified_at = ?,
                    subscription_environment = ?
                WHERE original_transaction_id = ?
            ''', (new_status, expires_at, now_iso(), environment, original_tx_id))
        else:
            conn.execute('''
                UPDATE groups
                SET subscription_last_verified_at = ?
                WHERE original_transaction_id = ?
            ''', (now_iso(), original_tx_id))

    print(f'[Notifications] {notification_type}/{subtype} -> {new_status} ({original_tx_id})')
    return jsonify({'ok': True})


def poll_subscription_status():
    """全有効グループのサブスク状態を Apple サーバーで定期検証する。

    Webhook の取りこぼしに備えて1時間毎に状態を再同期する。
    """
    print('[サブスク監視] 開始')
    while True:
        try:
            with get_db() as conn:
                rows = conn.execute('''
                    SELECT id, original_transaction_id, subscription_environment
                    FROM groups
                    WHERE original_transaction_id IS NOT NULL
                ''').fetchall()
            for row in rows:
                orig_tx = row['original_transaction_id']
                env     = row['subscription_environment'] or 'Production'
                try:
                    status = app_store_api.get_subscription_status(orig_tx, environment=env)
                    if not status:
                        continue
                    label = app_store_api.status_label(status['status'])
                    expires_at = _expires_iso(status.get('expires_date_ms'))
                    with get_db() as conn:
                        conn.execute('''
                            UPDATE groups
                            SET subscription_status = ?,
                                subscription_expires_at = ?,
                                subscription_last_verified_at = ?
                            WHERE id = ?
                        ''', (label, expires_at, now_iso(), row['id']))
                except Exception as e:
                    print(f'[サブスク監視] {orig_tx}: {e}')
        except Exception as e:
            print(f'[サブスク監視] エラー: {e}')
        time.sleep(3600)  # 1時間

@app.route('/api/groups/<group_id>/members', methods=['GET'])
def get_members(group_id):
    with get_db() as conn:
        rows = conn.execute(
            'SELECT * FROM members WHERE group_id = ?', (group_id,)
        ).fetchall()
    members = [{
        'id':              r['id'],
        'groupId':         r['group_id'],
        'name':            r['name'],
        'latitude':        r['latitude'],
        'longitude':       r['longitude'],
        'batteryLevel':    r['battery'],
        'updatedAt':       r['updated_at'],
        'safetyStatus':    r['safety_status'],
        'safetyUpdatedAt': r['safety_updated_at'],
        'isMe':            False
    } for r in rows]
    return jsonify(members)

# MARK: - デバイストークン

@app.route('/api/register-token', methods=['POST'])
def register_token():
    data = request.get_json()
    token     = data.get('token', '').strip()
    member_id = data.get('member_id', '').strip()
    group_id  = data.get('group_id', '').strip()
    if not all([token, member_id, group_id]):
        return jsonify({'error': 'missing fields'}), 400

    with get_db() as conn:
        conn.execute('''
            INSERT INTO device_tokens (member_id, group_id, token, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(member_id) DO UPDATE SET token = excluded.token, updated_at = excluded.updated_at
        ''', (member_id, group_id, token, now_iso()))
    return jsonify({'ok': True})

# MARK: - 位置情報

@app.route('/api/location', methods=['POST'])
def update_location():
    data      = request.get_json()
    member_id = data.get('memberId')
    group_id  = data.get('groupId')
    latitude  = data.get('latitude')
    longitude = data.get('longitude')
    battery   = data.get('batteryLevel')
    timestamp = data.get('timestamp', now_iso())

    if not all([member_id, group_id, latitude, longitude]):
        return jsonify({'error': 'missing fields'}), 400

    with get_db() as conn:
        member = conn.execute(
            'SELECT name, battery_alerted FROM members WHERE id = ? AND group_id = ?',
            (member_id, group_id)
        ).fetchone()
        if not member:
            return jsonify({'error': 'member not found'}), 404
        conn.execute(
            'UPDATE members SET latitude=?, longitude=?, battery=?, updated_at=? WHERE id=?',
            (latitude, longitude, battery, timestamp, member_id)
        )
        conn.execute(
            'INSERT INTO location_history (member_id, group_id, latitude, longitude, battery, recorded_at) VALUES (?, ?, ?, ?, ?, ?)',
            (member_id, group_id, latitude, longitude, battery, timestamp)
        )

        # バッテリー低下アラート（災害モード中のみ）
        if battery is not None and battery >= 0:
            active_disaster = conn.execute(
                'SELECT 1 FROM disaster_events WHERE group_id = ? AND is_active = 1', (group_id,)
            ).fetchone()
            if active_disaster:
                battery_pct   = int(battery * 100)
                alerted_str   = member['battery_alerted'] or ''
                alerted       = set(x for x in alerted_str.split(',') if x)
                crossed       = [t for t in BATTERY_THRESHOLDS if battery_pct <= t and str(t) not in alerted]
                if crossed:
                    for t in crossed:
                        alerted.add(str(t))
                    conn.execute(
                        'UPDATE members SET battery_alerted = ? WHERE id = ?',
                        (','.join(alerted), member_id)
                    )
                    tokens = conn.execute(
                        'SELECT token FROM device_tokens WHERE group_id = ? AND member_id != ?',
                        (group_id, member_id)
                    ).fetchall()
                    payload = {
                        'aps': {
                            'alert': {
                                'title': '⚡ バッテリー低下',
                                'body': f'{member["name"]}さんのバッテリーが残り{battery_pct}%です'
                            },
                            'sound': 'default'
                        },
                        'type': 'battery_alert'
                    }
                    for row in tokens:
                        threading.Thread(target=send_apns, args=(row['token'], payload), daemon=True).start()

    return jsonify({'ok': True})

# MARK: - 災害モード

@app.route('/api/disaster/activate', methods=['POST'])
def activate_disaster():
    data = request.get_json()
    group_id = data.get('group_id')
    if not group_id:
        return jsonify({'error': 'group_id is required'}), 400
    event_id = generate_id()
    with get_db() as conn:
        conn.execute(
            'INSERT INTO disaster_events (id, group_id, activated_at) VALUES (?, ?, ?)',
            (event_id, group_id, now_iso())
        )
    return jsonify({'ok': True})

@app.route('/api/disaster/deactivate', methods=['POST'])
def deactivate_disaster():
    data = request.get_json()
    group_id = data.get('group_id')
    if not group_id:
        return jsonify({'error': 'group_id is required'}), 400
    with get_db() as conn:
        conn.execute(
            'UPDATE disaster_events SET is_active=0, deactivated_at=? WHERE group_id=? AND is_active=1',
            (now_iso(), group_id)
        )
        conn.execute(
            'UPDATE members SET latitude=NULL, longitude=NULL, battery=NULL, updated_at=NULL, battery_alerted=NULL WHERE group_id=?',
            (group_id,)
        )
    return jsonify({'ok': True})

@app.route('/api/members/<member_id>', methods=['DELETE'])
def delete_member(member_id):
    with get_db() as conn:
        conn.execute('DELETE FROM device_tokens WHERE member_id = ?', (member_id,))
        conn.execute('DELETE FROM location_history WHERE member_id = ?', (member_id,))
        conn.execute('DELETE FROM members WHERE id = ?', (member_id,))
    return jsonify({'ok': True})

# MARK: - 移動履歴

@app.route('/api/members/<member_id>/history', methods=['GET'])
def get_member_history(member_id):
    hours = min(int(request.args.get('hours', 24)), 168)  # 最大7日
    since = (datetime.now(JST) - timedelta(hours=hours)).isoformat()
    with get_db() as conn:
        rows = conn.execute(
            '''SELECT id, latitude, longitude, battery, recorded_at
               FROM location_history
               WHERE member_id = ? AND recorded_at >= ?
               ORDER BY recorded_at ASC''',
            (member_id, since)
        ).fetchall()
    return jsonify([{
        'id':         r['id'],
        'latitude':   r['latitude'],
        'longitude':  r['longitude'],
        'battery':    r['battery'],
        'recordedAt': r['recorded_at']
    } for r in rows])

def cleanup_old_history():
    cutoff = (datetime.now(JST) - timedelta(days=7)).isoformat()
    with get_db() as conn:
        conn.execute('DELETE FROM location_history WHERE recorded_at < ?', (cutoff,))

# MARK: - 安否確認

@app.route('/api/safety', methods=['POST'])
def report_safety():
    data = request.get_json()
    member_id = data.get('member_id', '').strip()
    group_id  = data.get('group_id', '').strip()
    status    = data.get('status', '').strip()
    if not all([member_id, group_id, status]) or status not in ('safe', 'need_help'):
        return jsonify({'error': 'invalid params'}), 400

    with get_db() as conn:
        member = conn.execute('SELECT name FROM members WHERE id = ?', (member_id,)).fetchone()
        conn.execute(
            'UPDATE members SET safety_status=?, safety_updated_at=? WHERE id=?',
            (status, now_iso(), member_id)
        )
        tokens = conn.execute(
            'SELECT token FROM device_tokens WHERE group_id = ? AND member_id != ?',
            (group_id, member_id)
        ).fetchall()

    name         = member['name'] if member else '不明'
    status_label = '無事です' if status == 'safe' else '助けが必要'
    payload = {
        'aps': {
            'alert': {'title': '🔔 安否確認', 'body': f'{name}さんが「{status_label}」と報告しました'},
            'sound': 'default'
        },
        'type': 'safety_report',
        'member_id': member_id,
        'status': status
    }
    for row in tokens:
        send_apns(row['token'], payload)

    return jsonify({'ok': True})

# MARK: - 避難所

@app.route('/api/shelters/version', methods=['GET'])
def shelter_version():
    with get_db() as conn:
        row = conn.execute("SELECT value FROM shelter_meta WHERE key='version'").fetchone()
    return jsonify({'version': row['value'] if row else None})

@app.route('/api/shelters/download', methods=['GET'])
def shelter_download():
    import gzip
    with get_db() as conn:
        rows = conn.execute('SELECT * FROM shelters').fetchall()
    shelters = [{
        'id':          r['id'],
        'name':        r['name'],
        'address':     r['address'],
        'lat':         r['latitude'],
        'lng':         r['longitude'],
        'flood':       r['flood'],
        'landslide':   r['landslide'],
        'stormSurge':  r['storm_surge'],
        'earthquake':  r['earthquake'],
        'tsunami':     r['tsunami'],
        'fire':        r['fire'],
        'inlandFlood': r['inland_flood'],
        'volcano':     r['volcano'],
    } for r in rows]
    body = json.dumps(shelters, ensure_ascii=False).encode('utf-8')
    compressed = gzip.compress(body)
    from flask import Response
    return Response(
        compressed,
        mimetype='application/json',
        headers={'Content-Encoding': 'gzip', 'Content-Length': len(compressed)}
    )

@app.route('/api/shelters/nearby', methods=['GET'])
def shelters_nearby():
    try:
        lat    = float(request.args.get('lat'))
        lng    = float(request.args.get('lng'))
        radius = float(request.args.get('radius', 3000))  # メートル
    except (TypeError, ValueError):
        return jsonify({'error': 'invalid params'}), 400

    # 1度≒111km で簡易バウンディングボックス
    delta_lat = radius / 111000
    delta_lng = radius / (111000 * abs(__import__('math').cos(__import__('math').radians(lat))))
    with get_db() as conn:
        rows = conn.execute('''
            SELECT * FROM shelters
            WHERE latitude  BETWEEN ? AND ?
              AND longitude BETWEEN ? AND ?
        ''', (lat - delta_lat, lat + delta_lat, lng - delta_lng, lng + delta_lng)).fetchall()
    return jsonify([{
        'id': r['id'], 'name': r['name'], 'address': r['address'],
        'lat': r['latitude'], 'lng': r['longitude'],
        'earthquake': r['earthquake'], 'tsunami': r['tsunami'], 'flood': r['flood']
    } for r in rows])

# MARK: - 管理画面

ADMIN_TEMPLATE = '''
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SearchMe 管理画面</title>
<style>
  body { font-family: sans-serif; max-width: 960px; margin: 40px auto; padding: 0 16px; }
  h1 { color: #f97316; }
  h2 { margin-top: 32px; border-bottom: 2px solid #f97316; padding-bottom: 4px; }
  h3 { margin-top: 20px; color: #555; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
  th, td { padding: 8px 12px; border: 1px solid #ddd; text-align: left; font-size: 13px; }
  th { background: #f5f5f5; }
  .no-location { color: #999; }
  .has-location { color: #16a34a; }
</style>
</head>
<body>
<h1>SearchMe 管理画面</h1>

<h2>グループ別メンバー一覧（{{ groups|length }}グループ / {{ total_members }}名）</h2>
{% for g in groups %}
<h3>{{ g.name }}　<small style="color:#999">招待コード: {{ g.invite_code }} ／ {{ g.member_count }}名</small></h3>
<table>
  <tr><th>名前</th><th>位置情報</th><th>緯度</th><th>経度</th><th>バッテリー</th><th>最終更新</th></tr>
  {% for m in g.members %}
  <tr>
    <td>{{ m.name }}</td>
    <td class="{{ 'has-location' if m.latitude else 'no-location' }}">{{ '取得済み' if m.latitude else '未取得' }}</td>
    <td>{{ '%.4f'|format(m.latitude) if m.latitude else '-' }}</td>
    <td>{{ '%.4f'|format(m.longitude) if m.longitude else '-' }}</td>
    <td>{{ (m.battery * 100)|int if m.battery else '-' }}%</td>
    <td>{{ m.updated_at or '未取得' }}</td>
  </tr>
  {% endfor %}
</table>
{% endfor %}

<h2>デバイストークン（{{ tokens|length }}件）</h2>
<table>
  <tr><th>名前</th><th>グループ</th><th>トークン（先頭20文字）</th><th>更新日時</th></tr>
  {% for t in tokens %}
  <tr>
    <td>{{ t.member_name or '-' }}</td>
    <td>{{ t.group_name or '-' }}</td>
    <td>{{ t.token[:20] }}...</td>
    <td>{{ t.updated_at }}</td>
  </tr>
  {% endfor %}
</table>
</body>
</html>
'''

@app.route('/admin')
def admin():
    with get_db() as conn:
        group_rows  = conn.execute('SELECT * FROM groups ORDER BY created_at DESC').fetchall()
        member_rows = conn.execute('SELECT * FROM members ORDER BY name').fetchall()
        token_rows  = conn.execute('''
            SELECT dt.*, m.name AS member_name, g.name AS group_name
            FROM device_tokens dt
            LEFT JOIN members m ON dt.member_id = m.id
            LEFT JOIN groups g ON dt.group_id = g.id
            ORDER BY dt.updated_at DESC
        ''').fetchall()

    members_by_group = {}
    for m in member_rows:
        members_by_group.setdefault(m['group_id'], []).append(m)

    groups = []
    for g in group_rows:
        grp_members = members_by_group.get(g['id'], [])
        groups.append({
            'name': g['name'],
            'invite_code': g['invite_code'],
            'member_count': len(grp_members),
            'members': grp_members
        })

    return render_template_string(
        ADMIN_TEMPLATE,
        groups=groups,
        total_members=len(member_rows),
        tokens=token_rows
    )

# MARK: - 起動

init_db()
migrate_db()
cleanup_old_history()

# 地震監視スレッドを起動
earthquake_thread = threading.Thread(target=poll_earthquake, daemon=True)
earthquake_thread.start()

# サブスク監視スレッドを起動
subscription_thread = threading.Thread(target=poll_subscription_status, daemon=True)
subscription_thread.start()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5004, debug=False)
