import Foundation
import SQLite3

final class ShelterService {
    static let shared = ShelterService()

    private let base = "https://searchme.skyscanning.jp/api"
    private var db: OpaquePointer?
    private let dbPath: String
    private let versionKey = "shelterDataVersion"
    // 30日ごとに更新確認
    private let updateIntervalDays = 30

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = docs.appendingPathComponent("shelters.db").path
        openDB()
        createTable()
    }

    // MARK: - DB Setup

    private func openDB() {
        sqlite3_open(dbPath, &db)
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS shelters (
            id         INTEGER PRIMARY KEY,
            name       TEXT NOT NULL,
            address    TEXT,
            lat        REAL NOT NULL,
            lng        REAL NOT NULL,
            earthquake INTEGER DEFAULT 0,
            tsunami    INTEGER DEFAULT 0,
            flood      INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_lat ON shelters (lat);
        CREATE INDEX IF NOT EXISTS idx_lng ON shelters (lng);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Update Check

    func checkAndUpdateIfNeeded() async {
        guard shouldCheckUpdate() else { return }
        guard let serverVersion = await fetchServerVersion() else { return }
        let localVersion = UserDefaults.standard.string(forKey: versionKey) ?? ""
        if serverVersion != localVersion || count() == 0 {
            await downloadAndStore(version: serverVersion)
        }
    }

    private func shouldCheckUpdate() -> Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: "shelterLastCheck") as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) > Double(updateIntervalDays * 86400)
    }

    private func fetchServerVersion() async -> String? {
        guard let url = URL(string: "\(base)/shelters/version") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else { return nil }
        return version
    }

    private func downloadAndStore(version: String) async {
        guard let url = URL(string: "\(base)/shelters/download") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let shelters = try? JSONDecoder().decode([Shelter].self, from: data) else { return }
        storeAll(shelters)
        UserDefaults.standard.set(version, forKey: versionKey)
        UserDefaults.standard.set(Date(), forKey: "shelterLastCheck")
        print("[避難所] \(shelters.count)件を取得・保存")
    }

    // MARK: - DB Operations

    private func storeAll(_ shelters: [Shelter]) {
        sqlite3_exec(db, "DELETE FROM shelters", nil, nil, nil)
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        let sql = "INSERT INTO shelters (id,name,address,lat,lng,earthquake,tsunami,flood) VALUES (?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        for s in shelters {
            sqlite3_bind_int(stmt,  1, Int32(s.id))
            sqlite3_bind_text(stmt, 2, (s.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, ((s.address ?? "") as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 4, s.lat)
            sqlite3_bind_double(stmt, 5, s.lng)
            sqlite3_bind_int(stmt, 6, Int32(s.earthquake))
            sqlite3_bind_int(stmt, 7, Int32(s.tsunami))
            sqlite3_bind_int(stmt, 8, Int32(s.flood))
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        sqlite3_finalize(stmt)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func nearbyShelters(lat: Double, lng: Double, radiusKm: Double = 3.0) -> [Shelter] {
        let deltaLat = radiusKm / 111.0
        let deltaLng = radiusKm / (111.0 * abs(cos(lat * .pi / 180)))
        let sql = """
        SELECT * FROM shelters
        WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?
        LIMIT 50
        """
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_double(stmt, 1, lat - deltaLat)
        sqlite3_bind_double(stmt, 2, lat + deltaLat)
        sqlite3_bind_double(stmt, 3, lng - deltaLng)
        sqlite3_bind_double(stmt, 4, lng + deltaLng)

        var results: [Shelter] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Shelter(
                id:         Int(sqlite3_column_int(stmt, 0)),
                name:       String(cString: sqlite3_column_text(stmt, 1)),
                address:    sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                lat:        sqlite3_column_double(stmt, 3),
                lng:        sqlite3_column_double(stmt, 4),
                earthquake: Int(sqlite3_column_int(stmt, 5)),
                tsunami:    Int(sqlite3_column_int(stmt, 6)),
                flood:      Int(sqlite3_column_int(stmt, 7))
            ))
        }
        sqlite3_finalize(stmt)
        return results
    }

    func count() -> Int {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM shelters", -1, &stmt, nil)
        sqlite3_step(stmt)
        let c = Int(sqlite3_column_int(stmt, 0))
        sqlite3_finalize(stmt)
        return c
    }
}
