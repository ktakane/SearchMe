import sqlite3, zipfile, io, urllib.request, os, tempfile
import shapefile

DB_PATH = '/home/skyscanning/searchme_server/searchme.db'
BASE_URL = 'https://nlftp.mlit.go.jp/ksj/gml/data/P20/P20-12/P20-12_{:02d}_GML.zip'
from datetime import datetime, timezone, timedelta
JST = timezone(timedelta(hours=9))

conn = sqlite3.connect(DB_PATH)
conn.execute('DELETE FROM shelters')
conn.execute("DELETE FROM shelter_meta WHERE key='version'")

total = 0
for pref in range(1, 48):
    url = BASE_URL.format(pref)
    try:
        print(f'[{pref:02d}/47] ダウンロード中...', end=' ', flush=True)
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = resp.read()
        with tempfile.TemporaryDirectory() as tmp:
            zf = zipfile.ZipFile(io.BytesIO(data))
            zf.extractall(tmp)
            shp_files = [f for f in os.listdir(tmp) if f.endswith('.shp')]
            if not shp_files:
                print('SHPなし')
                continue
            sf = shapefile.Reader(os.path.join(tmp, shp_files[0]), encoding='cp932')
            count = 0
            for sr in sf.shapeRecords():
                r = sr.record.as_dict()
                name    = (r.get('P20_002') or '').strip()
                address = (r.get('P20_003') or '').strip()
                lat     = r.get('緯度') or (sr.shape.points[0][1] if sr.shape.points else None)
                lng     = r.get('経度') or (sr.shape.points[0][0] if sr.shape.points else None)
                if not name or not lat or not lng:
                    continue
                conn.execute(
                    'INSERT INTO shelters (name,address,latitude,longitude,earthquake,tsunami,flood,volcano) VALUES (?,?,?,?,?,?,?,?)',
                    (name, address, lat, lng,
                     int(r.get('P20_007') or 0),
                     int(r.get('P20_008') or 0),
                     int(r.get('P20_009') or 0),
                     int(r.get('P20_010') or 0))
                )
                count += 1
            total += count
            print(f'{count}件')
    except Exception as e:
        print(f'エラー: {e}')

version = datetime.now(JST).strftime('%Y-%m-%dT%H:%M:%S+09:00')
conn.execute("INSERT INTO shelter_meta (key,value) VALUES ('version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (version,))
conn.commit()
conn.close()
print(f'\n完了: 合計{total}件 (version={version})')
