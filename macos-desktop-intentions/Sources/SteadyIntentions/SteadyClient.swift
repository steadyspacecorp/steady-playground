import Foundation

// MARK: - API models (decoded against the v2 OpenAPI spec at https://app.steady.space/openapi.yml)

/// `GET /me` returns the person object directly at the top level.
struct PersonRef: Decodable {
    let id: String
    let name: String?
    let url: String?
}

/// A single check-in. `GET /check-ins` returns a bare array of these. Most
/// prose fields are nullable and some keys are omitted when empty, so
/// everything past `id`/`date` is optional.
struct CheckIn: Decodable {
    let id: String
    let date: String
    let person: PersonRef?           // nested {id, name} object
    let intentions: String?          // "What do you intend to do next?" (markdown)
}

/// The shape we hand to the UI.
struct DayIntentions: Equatable {
    let date: String
    let intentions: String?
}

enum SteadyError: LocalizedError {
    case missingToken
    case http(Int)
    case noCheckInToday

    var errorDescription: String? {
        switch self {
        case .missingToken: return "No Steady token set. Use the menu bar → Set Token…"
        case .http(let code): return "Steady API returned HTTP \(code)."
        case .noCheckInToday: return "No check-in for today yet."
        }
    }
}

/// Result of a poll: either fresh content, or "nothing changed" (ETag 304).
enum PollResult {
    case unchanged
    case updated(DayIntentions?)   // nil == no check-in today
    case failure(Error)
}

/// Thin async client over the Steady v2 REST API.
/// Auth is a Personal Access Token (`steady_pat_…`) sent as a Bearer token.
actor SteadyClient {
    static let baseURL = URL(string: "https://service.steady.space/api/v2")!

    private let session: URLSession
    private var cachedPersonID: String?
    private var lastETag: String?

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Force a re-fetch on the next poll regardless of ETag (e.g. after the
    /// token changes or the user asks for a manual refresh).
    func invalidate() {
        lastETag = nil
        cachedPersonID = nil
    }

    /// Today's date in the user's local timezone, formatted `YYYY-MM-DD`.
    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .iso8601)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func authorizedRequest(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let token = Keychain.token, !token.isEmpty else {
            throw SteadyError.missingToken
        }
        var comps = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func resolvePersonID() async throws -> String {
        if let id = cachedPersonID { return id }
        let req = try authorizedRequest(path: "me")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SteadyError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw SteadyError.http(http.statusCode) }
        let me = try JSONDecoder().decode(PersonRef.self, from: data)
        cachedPersonID = me.id
        return me.id
    }

    /// Poll for today's check-in. Uses `If-None-Match` so an unchanged
    /// response comes back as a cheap 304.
    func poll() async -> PollResult {
        do {
            let personID = try await resolvePersonID()
            let today = todayString()
            var req = try authorizedRequest(path: "check-ins", query: [
                URLQueryItem(name: "people_ids[]", value: personID),
                URLQueryItem(name: "since", value: today),
                URLQueryItem(name: "until", value: today),
                URLQueryItem(name: "per_page", value: "1"),
            ])
            if let etag = lastETag {
                req.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw SteadyError.http(-1) }

            if http.statusCode == 304 {
                return .unchanged
            }
            guard (200..<300).contains(http.statusCode) else {
                throw SteadyError.http(http.statusCode)
            }
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                lastETag = etag
            }

            // The endpoint returns a bare array; it's already filtered to me and
            // to today, but pick today's defensively and dedupe by id.
            let checkIns = try JSONDecoder().decode([CheckIn].self, from: data)
            let mine = checkIns
                .filter { $0.date == today }
                .reduce(into: [String: CheckIn]()) { $0[$1.id] = $1 }
                .values
                .first

            guard let c = mine else { return .updated(nil) }
            return .updated(DayIntentions(
                date: c.date,
                intentions: c.intentions?.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } catch {
            return .failure(error)
        }
    }
}
