import Foundation

struct DigestEntry: Decodable {
    let id: String
    let category: String?
    let publishedAt: Date?
    let readAt: Date?
    let resource: Resource?

    struct Resource: Decodable {
        let type: String?
        let title: String?
        let body: String?
        let progress: Int?
        let confidence: Int?
        let confidenceDescription: String?
        let url: String?
        let goal: Named?
        let person: Named?
    }

    struct Named: Decodable {
        let id: String?
        let title: String?
        let name: String?
    }
}

enum DigestError: LocalizedError {
    case missingToken
    case http(Int, String?)
    case transport(Error)
    case decoding(Error)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingToken: return "No Steady access token set. Use Set Token… in the menu."
        case .http(let code, let body):
            return "Steady API returned HTTP \(code)\(body.map { ": \($0)" } ?? "")"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        case .decoding(let err): return "Could not decode response: \(err.localizedDescription)"
        case .empty: return "No digest entries available."
        }
    }
}

struct DigestClient {
    static let baseURL = URL(string: "https://service.steady.space/api/v2/")!

    let tokenProvider: () -> String?

    func fetchLatest(completion: @escaping (Result<DigestEntry, DigestError>) -> Void) {
        guard let token = tokenProvider(), !token.isEmpty else {
            completion(.failure(.missingToken))
            return
        }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("digest"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(.transport(error))); return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.http(0, nil))); return
            }
            let bodyText = data.flatMap { String(data: $0, encoding: .utf8) }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.http(http.statusCode, bodyText))); return
            }
            guard let data = data else { completion(.failure(.empty)); return }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                let entries = try decoder.decode([DigestEntry].self, from: data)
                if let first = entries.first {
                    completion(.success(first))
                } else {
                    completion(.failure(.empty))
                }
            } catch {
                completion(.failure(.decoding(error)))
            }
        }.resume()
    }
}
