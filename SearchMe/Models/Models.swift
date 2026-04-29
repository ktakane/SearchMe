import Foundation

struct FamilyMember: Identifiable, Codable {
    var id: String
    var name: String
    var latitude: Double?
    var longitude: Double?
    var batteryLevel: Float?
    var updatedAt: String?
    var isMe: Bool

    var hasLocation: Bool { latitude != nil && longitude != nil }

    var updatedAtDate: Date? {
        guard let s = updatedAt else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    var updatedAtDisplay: String {
        guard let date = updatedAtDate else { return "未取得" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "たった今" }
        if diff < 3600 { return "\(Int(diff / 60))分前" }
        if diff < 86400 { return "\(Int(diff / 3600))時間前" }
        return "\(Int(diff / 86400))日前"
    }
}

struct FamilyGroup: Codable {
    var id: String
    var name: String
    var inviteCode: String
}

struct LocationPayload: Codable {
    var memberId: String
    var groupId: String
    var latitude: Double
    var longitude: Double
    var batteryLevel: Float
    var timestamp: String
}

struct DisasterEvent: Codable {
    var id: String
    var title: String
    var detectedAt: String
    var isActive: Bool
}
