import Foundation

final class PaperclipHTTPClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func get<Value: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Value.Type,
        completion: @escaping (Result<Value, Error>) -> Void
    ) {
        switch request(baseURL: baseURL, path: path, queryItems: queryItems) {
        case let .failure(error):
            completion(.failure(error))
        case let .success(request):
            session.dataTask(with: request) { data, response, error in
                completion(Self.decodeResponse(data: data, response: response, error: error, as: type))
            }.resume()
        }
    }

    func getLossyArray<Value: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Value.Type,
        completion: @escaping (Result<[Value], Error>) -> Void
    ) {
        switch request(baseURL: baseURL, path: path, queryItems: queryItems) {
        case let .failure(error):
            completion(.failure(error))
        case let .success(request):
            session.dataTask(with: request) { data, response, error in
                completion(Self.decodeLossyArrayResponse(data: data, response: response, error: error, as: type))
            }.resume()
        }
    }

    func request(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) -> Result<URLRequest, Error> {
        guard PaperclipNetworkPolicy.validRelativePath(path) else {
            return .failure(PaperclipServiceError.invalidConfiguration)
        }
        let pathURL = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            return .failure(PaperclipServiceError.invalidConfiguration)
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else {
            return .failure(PaperclipServiceError.invalidConfiguration)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return .success(request)
    }

    private static func decodeResponse<Value: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        as type: Value.Type
    ) -> Result<Value, Error> {
        switch validatedData(data: data, response: response, error: error) {
        case let .failure(error):
            return .failure(error)
        case let .success(data):
            do {
                return .success(try JSONDecoder().decode(type, from: data))
            } catch {
                return .failure(error)
            }
        }
    }

    private static func decodeLossyArrayResponse<Value: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        as type: Value.Type
    ) -> Result<[Value], Error> {
        switch validatedData(data: data, response: response, error: error) {
        case let .failure(error):
            return .failure(error)
        case let .success(data):
            do {
                guard let raw = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                    return .failure(PaperclipServiceError.invalidResponse)
                }
                let decoder = JSONDecoder()
                let values = raw.compactMap { item -> Value? in
                    guard JSONSerialization.isValidJSONObject(item),
                          let itemData = try? JSONSerialization.data(withJSONObject: item)
                    else { return nil }
                    return try? decoder.decode(type, from: itemData)
                }
                return .success(values)
            } catch {
                return .failure(error)
            }
        }
    }

    private static func validatedData(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<Data, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(PaperclipServiceError.http(http.statusCode))
        }
        guard let data else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        return .success(data)
    }
}
