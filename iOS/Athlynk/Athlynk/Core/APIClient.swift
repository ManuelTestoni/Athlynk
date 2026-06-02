//
//  APIClient.swift
//  Thin async wrapper over the Django /api/v1 backend.
//
//  Base URL is http://localhost:8000 in development (the running web app).
//  All authenticated calls attach `Authorization: Bearer <token>`.
//

import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "URL non valido"
        case .http(let code, let msg): return msg.isEmpty ? "Errore server (\(code))" : msg
        case .decoding(let d): return "Risposta non leggibile: \(d)"
        case .transport(let t): return t
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Override-able so a physical device can point at the host's LAN IP.
    var baseURL = "http://localhost:8000"
    var token: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()

    // MARK: Core request

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
        guard (200..<300).contains(http.statusCode) else {
            var msg = ""
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let dict = obj as? [String: Any],
               let err = dict["error"] as? String {
                msg = err
            }
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    // MARK: Endpoints

    func login(email: String, password: String) async throws -> LoginResponse {
        let data = try await request("/api/v1/auth/login", method: "POST",
                                     body: ["email": email, "password": password])
        return try decode(LoginResponse.self, from: data)
    }

    func me() async throws -> MeResponse {
        try decode(MeResponse.self, from: try await request("/api/v1/me"))
    }

    func workouts() async throws -> [WorkoutPlanDTO] {
        try decode(WorkoutsResponse.self, from: try await request("/api/v1/workouts")).plans
    }

    func nutrition() async throws -> [NutritionPlanDTO] {
        try decode(NutritionResponse.self, from: try await request("/api/v1/nutrition")).plans
    }

    func checks() async throws -> [CheckDTO] {
        try decode(ChecksResponse.self, from: try await request("/api/v1/checks")).pending
    }

    func notifications() async throws -> [NotificationDTO] {
        try decode(NotificationsResponse.self, from: try await request("/api/v1/notifications")).notifications
    }

    func conversations() async throws -> [ConversationDTO] {
        try decode(ConversationsResponse.self, from: try await request("/api/v1/conversations")).conversations
    }

    func messages(conversation: Int) async throws -> [MessageDTO] {
        try decode(MessagesResponse.self,
                   from: try await request("/api/v1/conversations/\(conversation)/messages")).messages
    }

    func send(conversation: Int, body: String) async throws {
        _ = try await request("/api/v1/conversations/\(conversation)/send",
                              method: "POST", body: ["body": body])
    }
}
