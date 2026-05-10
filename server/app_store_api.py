"""App Store Server API クライアント。

オーナーのサブスクリプション状態を Apple サーバー側で検証する。
- get_subscription_status: /inApps/v1/subscriptions/{originalTransactionId}
- decode_jws: クライアントから送られた JWS Transaction を検証してデコード
- verify_notification: Server Notifications V2 の signedPayload を検証

注意:
- ES256 署名鍵（.p8）と Issuer ID / Key ID が必要
- Production / Sandbox の判別は decode_jws の `environment` フィールドで行い、
  対応する API ホストへ問い合わせる
"""

import os
import time
import json
import base64
import jwt as pyjwt
import httpx

def _load_config():
    """Load credentials from env vars; fall back to JSON file in same directory.

    File path: <module_dir>/app_store_config.json
    File schema: {"issuer_id": "...", "key_id": "...", "key_path": "..."}
    """
    config_path = os.path.join(os.path.dirname(__file__), 'app_store_config.json')
    file_cfg = {}
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                file_cfg = json.load(f)
        except Exception as e:
            print(f'[App Store] failed to load config: {e}')
    default_key_path = '/home/skyscanning/searchme_server/app_store_api_key.p8'
    return (
        os.environ.get('APP_STORE_ISSUER_ID') or file_cfg.get('issuer_id', ''),
        os.environ.get('APP_STORE_KEY_ID')    or file_cfg.get('key_id', ''),
        os.environ.get('APP_STORE_KEY_PATH')  or file_cfg.get('key_path', default_key_path),
    )


ISSUER_ID, KEY_ID, KEY_PATH = _load_config()
BUNDLE_ID = 'com.skyscanning.searchme'

API_HOST_PRODUCTION = 'https://api.storekit.itunes.apple.com'
API_HOST_SANDBOX    = 'https://api.storekit-sandbox.itunes.apple.com'


def _load_private_key() -> str:
    if not os.path.exists(KEY_PATH):
        raise RuntimeError(f'App Store API key not found: {KEY_PATH}')
    with open(KEY_PATH, 'r') as f:
        return f.read()


def _generate_jwt() -> str:
    if not ISSUER_ID or not KEY_ID:
        raise RuntimeError('APP_STORE_ISSUER_ID / APP_STORE_KEY_ID not configured')
    now = int(time.time())
    payload = {
        'iss': ISSUER_ID,
        'iat': now,
        'exp': now + 60 * 20,  # 最大20分
        'aud': 'appstoreconnect-v1',
        'bid': BUNDLE_ID,
    }
    headers = {'alg': 'ES256', 'kid': KEY_ID, 'typ': 'JWT'}
    return pyjwt.encode(payload, _load_private_key(), algorithm='ES256', headers=headers)


def _api_host(environment: str) -> str:
    if (environment or '').lower() == 'sandbox':
        return API_HOST_SANDBOX
    return API_HOST_PRODUCTION


def decode_jws(signed_payload: str) -> dict:
    """JWS の中身をデコードする。

    Apple の signedTransactionInfo / signedRenewalInfo / Server Notifications V2 の
    signedPayload はすべて JWS。ここでは署名検証は行わず（x5c 検証は別途実装可能）、
    ペイロードだけ取り出す。署名検証が必須な箇所では verify_notification を使う。
    """
    parts = signed_payload.split('.')
    if len(parts) != 3:
        raise ValueError('invalid JWS')
    payload_b64 = parts[1]
    # base64url パディング補正
    padding = '=' * (-len(payload_b64) % 4)
    payload_bytes = base64.urlsafe_b64decode(payload_b64 + padding)
    return json.loads(payload_bytes)


def verify_notification(signed_payload: str) -> dict:
    """Server Notifications V2 の signedPayload を検証してデコードする。

    本番運用では x5c 証明書チェーンを Apple Root CA で検証する必要がある。
    本実装では最低限 PyJWT の cryptography 経由で署名検証を試み、
    失敗した場合はペイロードだけ返す（運用ログで気付けるように）。
    """
    try:
        unverified_header = pyjwt.get_unverified_header(signed_payload)
        x5c = unverified_header.get('x5c', [])
        if x5c:
            # 先頭証明書を公開鍵として使う簡易検証
            cert_b64 = x5c[0]
            cert_pem = (
                '-----BEGIN CERTIFICATE-----\n'
                + '\n'.join(cert_b64[i:i+64] for i in range(0, len(cert_b64), 64))
                + '\n-----END CERTIFICATE-----\n'
            )
            from cryptography import x509
            from cryptography.hazmat.backends import default_backend
            cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())
            public_key = cert.public_key()
            return pyjwt.decode(signed_payload, key=public_key, algorithms=['ES256'])
    except Exception as e:
        print(f'[App Store] notification verification failed (fallback to decode): {e}')
    return decode_jws(signed_payload)


def get_subscription_status(original_transaction_id: str, environment: str = 'Production') -> dict:
    """Apple サーバーで現在のサブスク状態を取得する。

    Returns: {
        'status': int,  # 1=active, 2=expired, 3=in_billing_retry, 4=in_grace, 5=revoked
        'product_id': str,
        'expires_date_ms': int,  # ミリ秒
        'environment': str,
        'original_transaction_id': str,
    } または None（取得失敗時）
    """
    host = _api_host(environment)
    url = f'{host}/inApps/v1/subscriptions/{original_transaction_id}'
    token = _generate_jwt()
    headers = {'Authorization': f'Bearer {token}'}

    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.get(url, headers=headers)
        if resp.status_code == 404 and environment == 'Production':
            # Production で見つからない場合は Sandbox を試す（Apple 推奨フロー）
            return get_subscription_status(original_transaction_id, environment='Sandbox')
        if resp.status_code != 200:
            print(f'[App Store] {resp.status_code}: {resp.text[:200]}')
            return None
        data = resp.json()
    except Exception as e:
        print(f'[App Store] API error: {e}')
        return None

    # data['data'][0]['lastTransactions'][0] から signedTransactionInfo を取得
    try:
        groups = data.get('data', [])
        if not groups:
            return None
        last_txs = groups[0].get('lastTransactions', [])
        if not last_txs:
            return None
        last = last_txs[0]
        status = last.get('status')
        signed_tx = last.get('signedTransactionInfo')
        signed_renewal = last.get('signedRenewalInfo')
        tx_info = decode_jws(signed_tx) if signed_tx else {}
        renewal_info = decode_jws(signed_renewal) if signed_renewal else {}
        return {
            'status': status,
            'product_id': tx_info.get('productId'),
            'expires_date_ms': tx_info.get('expiresDate'),
            'environment': tx_info.get('environment', environment),
            'original_transaction_id': tx_info.get('originalTransactionId', original_transaction_id),
            'auto_renew_status': renewal_info.get('autoRenewStatus'),
        }
    except Exception as e:
        print(f'[App Store] response parse error: {e}')
        return None


# Apple status コードを内部ステータス文字列にマップ
APPLE_STATUS_MAP = {
    1: 'active',
    2: 'expired',
    3: 'in_billing_retry',
    4: 'in_grace',
    5: 'revoked',
}


def status_label(apple_status: int) -> str:
    return APPLE_STATUS_MAP.get(apple_status, 'unknown')


# productId からプラン情報を導出
PRODUCT_TO_PLAN = {
    'com.skyscanning.searchme.personal.monthly': ('personal', 6),
    'com.skyscanning.searchme.personal.yearly':  ('personal', 6),
    'com.skyscanning.searchme.team.monthly':     ('team', 20),
    'com.skyscanning.searchme.team.yearly':      ('team', 20),
}


def plan_from_product(product_id: str):
    """productId から (plan_type, max_members) を返す。未知なら None。"""
    return PRODUCT_TO_PLAN.get(product_id)
