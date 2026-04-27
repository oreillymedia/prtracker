import Foundation

final class StubURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    /// URL.absoluteString → Stub
    nonisolated(unsafe) static var responses: [String: Stub] = [:]
    /// Captured requests (for assertions)
    nonisolated(unsafe) static var captured: [URLRequest] = []

    static func reset() {
        responses.removeAll()
        captured.removeAll()
    }

    static func register(url: String, status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        responses[url] = Stub(status: status, headers: headers, body: body)
    }

    static func register(url: String, status: Int = 200, headers: [String: String] = [:], json: String) {
        register(url: url, status: status, headers: headers, body: json.data(using: .utf8)!)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured.append(request)
        guard let url = request.url?.absoluteString,
              let stub = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension URLSessionConfiguration {
    static var stubbed: URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        return c
    }
}
