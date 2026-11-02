import Foundation

// Lightweight Supabase REST client. Uses the publishable key from Secrets.swift: the app
// ships to testers, so its key is public, and RLS policies (data-layer migrations 00116,
// 00149) confine it to this app's own tables.
struct SupabaseClient {
    static let shared = SupabaseClient()

    static let projectURL = "https://felyggqjjhltwokdfhop.supabase.co"
    private let baseURL = projectURL + "/rest/v1/"

    /// Public URL of an object in a public storage bucket.
    static func publicObjectURL(bucket: String, object: String) -> URL? {
        let enc = object.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? object
        return URL(string: "\(projectURL)/storage/v1/object/public/\(bucket)/\(enc)")
    }

    enum SBError: Error, LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Supabase HTTP \(code): \(body)"
            }
        }
    }

    private func request(_ path: String, method: String, body: Data? = nil, prefer: String? = nil) -> URLRequest {
        // Concatenate as a string — appendingPathComponent percent-encodes `?` and `&`,
        // which breaks PostgREST query strings like `wines?id=eq.X`.
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(Secrets.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabaseKey)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        return req
    }

    func get<T: Decodable>(path: String) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: request(path, method: "GET"))
        try Self.check(resp, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// GET that keeps the last good answer on disk, for a read the app must have offline (the menu,
    /// cocktails, the prompt, the catalog). A response that decodes and passes `usable` is saved under
    /// `key`; when the request fails, the saved copy is returned instead, and failing that the copy
    /// `scripts/seed.sh` put in the bundle at build time (`Seed/<key>.json`). Nil only when none exist.
    func getCached<T: Decodable>(path: String, key: String, usable: (T) -> Bool = { _ in true }) async -> T? {
        if let fetched = try? await URLSession.shared.data(for: request(path, method: "GET")),
           (try? Self.check(fetched.1, data: fetched.0)) != nil,
           case let data = fetched.0,
           let value = try? JSONDecoder().decode(T.self, from: data), usable(value) {
            ResponseCache.save(data, key: key)
            return value
        }
        return cached(key: key)
    }

    /// The saved copy of a `getCached` read (or the bundled seed), without touching the network: what
    /// a store shows the moment it opens, before its fetch lands.
    func cached<T: Decodable>(key: String) -> T? {
        for data in [ResponseCache.load(key: key), ResponseCache.seed(key: key)].compactMap({ $0 }) {
            if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        }
        return nil
    }

    @discardableResult
    func patch(path: String, body: [String: Any?]) async throws -> Data {
        // Convert nullable values; Supabase accepts JSON null to clear a column.
        let clean: [String: Any] = body.mapValues { $0 ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: clean)
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "PATCH", body: data, prefer: "return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    /// PATCH that returns the affected rows as JSON. Useful for detecting "not found" (empty array).
    func patchReturning(path: String, body: [String: Any?]) async throws -> [[String: Any]] {
        let clean: [String: Any] = body.mapValues { $0 ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: clean)
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "PATCH", body: data, prefer: "return=representation"))
        try Self.check(http, data: resp)
        return (try? JSONSerialization.jsonObject(with: resp) as? [[String: Any]]) ?? []
    }

    @discardableResult
    func upsert(path: String, body: [[String: Any]], onConflict: String) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        let p = "\(path)?on_conflict=\(onConflict)"
        let (resp, http) = try await URLSession.shared.data(for: request(p, method: "POST", body: data, prefer: "resolution=merge-duplicates,return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    /// Plain INSERT. app_logs is insert-only for the anon key, so it cannot upsert.
    @discardableResult
    func insert(path: String, body: [[String: Any]]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "POST", body: data, prefer: "return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    @discardableResult
    func delete(path: String) async throws -> Data {
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "DELETE", prefer: "return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SBError.http(http.statusCode, body)
        }
    }
}

/// Last good responses of `SupabaseClient.getCached`, one file per key in Application Support (not
/// Caches, which the system empties when space runs low: this copy is what the app runs on offline).
enum ResponseCache {
    private static let dir: URL? = {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let d = base.appendingPathComponent("SupabaseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func save(_ data: Data, key: String) {
        guard let url = dir?.appendingPathComponent(key + ".json") else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(key: String) -> Data? {
        guard let url = dir?.appendingPathComponent(key + ".json") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func seed(key: String) -> Data? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "json", subdirectory: "Seed") else { return nil }
        return try? Data(contentsOf: url)
    }
}
