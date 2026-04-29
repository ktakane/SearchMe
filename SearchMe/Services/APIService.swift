import Foundation

final class APIService {
    static let shared = APIService()
    private let base = "https://searchme.skyscanning.jp/api"

    private init() {}

    func createGroup(name: String, ownerName: String) async throws -> (FamilyGroup, FamilyMember) {
        struct CreateResponse: Codable { var group: FamilyGroup; var member: FamilyMember }
        let body = ["name": name, "owner_name": ownerName]
        let resp: CreateResponse = try await post(path: "/groups", body: body)
        return (resp.group, resp.member)
    }

    func joinGroup(inviteCode: String, name: String) async throws -> (FamilyGroup, FamilyMember) {
        struct JoinResponse: Codable { var group: FamilyGroup; var member: FamilyMember }
        let body = ["invite_code": inviteCode, "name": name]
        let resp: JoinResponse = try await post(path: "/groups/join", body: body)
        return (resp.group, resp.member)
    }

    func registerToken(token: String, memberId: String, groupId: String) async throws {
        let body = ["token": token, "member_id": memberId, "group_id": groupId]
        let _: EmptyResponse = try await post(path: "/register-token", body: body)
    }

    func fetchMembers(groupId: String) async throws -> [FamilyMember] {
        return try await get(path: "/groups/\(groupId)/members")
    }

    func sendLocation(_ payload: LocationPayload) async throws {
        let _: EmptyResponse = try await post(path: "/location", body: payload)
    }

    func activateDisaster(groupId: String) async throws {
        let body = ["group_id": groupId]
        let _: EmptyResponse = try await post(path: "/disaster/activate", body: body)
    }

    func deactivateDisaster(groupId: String) async throws {
        let body = ["group_id": groupId]
        let _: EmptyResponse = try await post(path: "/disaster/deactivate", body: body)
    }

    func reportSafety(memberId: String, groupId: String, status: String) async throws {
        let body = ["member_id": memberId, "group_id": groupId, "status": status]
        let _: EmptyResponse = try await post(path: "/safety", body: body)
    }

    func leaveGroup(memberId: String) async throws {
        guard let url = URL(string: base + "/members/\(memberId)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (data, _) = try await URLSession.shared.data(for: req)
        let _ = try JSONDecoder().decode(EmptyResponse.self, from: data)
    }

    // MARK: - Private

    private struct EmptyResponse: Codable {}

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
