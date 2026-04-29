"""
国土数値情報「指定緊急避難場所データ（P20）」取込スクリプト

使い方:
  1. https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P20.html
     から全国CSVをダウンロードして解凍
  2. python3 import_shelters.py <CSVファイルパス>

CSVカラム順（国土数値情報 P20形式）:
  行政コード, 都道府県名, 市区町村名, 施設名, 住所,
  洪水, 崖崩れ等, 高潮, 地震, 津波, 大規模な火事, 内水氾濫, 火山現象,
  緯度, 経度
"""

import sqlite3
import csv
import sys
import os
from datetime import datetime, timezone, timedelta

DB_PATH = os.path.join(os.path.dirname(__file__), 'searchme.db')
JST = timezone(timedelta(hours=9))


def flag(val: str) -> int:
    return 1 if str(val).strip() in ('1', '○', '◎', 'true', 'True') else 0


def import_csv(csv_path: str):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('DELETE FROM shelters')

    count = 0
    with open(csv_path, encoding='utf-8-sig', newline='') as f:
        reader = csv.reader(f)
        next(reader)  # ヘッダーをスキップ
        for row in reader:
            if len(row) < 15:
                continue
            try:
                name    = row[3].strip()
                address = row[4].strip()
                lat     = float(row[13])
                lng     = float(row[14])
            except (ValueError, IndexError):
                continue
            if not name or not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
                continue

            conn.execute('''
                INSERT INTO shelters
                    (name, address, latitude, longitude,
                     flood, landslide, storm_surge, earthquake,
                     tsunami, fire, inland_flood, volcano)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                name, address, lat, lng,
                flag(row[5]),  # 洪水
                flag(row[6]),  # 崖崩れ等
                flag(row[7]),  # 高潮
                flag(row[8]),  # 地震
                flag(row[9]),  # 津波
                flag(row[10]), # 大規模な火事
                flag(row[11]), # 内水氾濫
                flag(row[12]), # 火山現象
            ))
            count += 1

    version = datetime.now(JST).strftime('%Y-%m-%dT%H:%M:%S+09:00')
    conn.execute('''
        INSERT INTO shelter_meta (key, value) VALUES ('version', ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ''', (version,))
    conn.commit()
    conn.close()
    print(f'取込完了: {count}件 (version={version})')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('使い方: python3 import_shelters.py <CSVファイルパス>')
        sys.exit(1)
    import_csv(sys.argv[1])
