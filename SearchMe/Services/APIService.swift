import Foundation

enum APIError: LocalizedError {
    case groupFull(max: Int)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .groupFull(let max):
            return "グループの人数上限（\(max)名）に達しています"
        case .serverError(let code):
            return "サーバーエラー (\(code))"
        }
    }
}

final class APIService {
    static let shared = APIService()
    private let base = "https://searchme.skyscanning.jp/api"

    private init() {}

    func createGroup(name: String, ownerName: String, maxMembers: Int) async throws -> (FamilyGroup, FamilyMember) {
        struct Body: Encodable { var name: String; var owner_name: String; var max_members: Int }
        struct Response: Codable { var group: FamilyGroup; var member: FamilyMember }
        let resp: Response = try await post(path: "/groups", body: Body(name: name, owner_name: ownerName, max_members: maxMembers))
        return (resp.group, resp.member)
    }

    func fetchHistory(memberId: String, hours: Int) async throws -> [HistoryPoint] {
        return try await get(path: "/members/\(memberId)/history?hours=\(hours)")
    }

    func updateGroupPlan(groupId: String, maxMembers: Int) async throws {
        struct Body: Encodable { var max_members: Int }
        let _: EmptyResponse = try await put(path: "/groups/\(groupId)/plan", body: Body(max_members: maxMembers))
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
    private struct GroupFullErrorBody: Decodable { var error: String; var max_members: Int? }

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
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            if let err = try? JSONDecoder().decode(GroupFullErrorBody.self, from: data),
               err.error == "group is full" {
                throw APIError.groupFull(max: err.max_members ?? 0)
            }
            throw APIError.serverError(403)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
