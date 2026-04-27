import Foundation
import Synchronization

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
    /// Async-safe mutex that does NOT suffer from actor reentrancy: a Token is
    /// granted to one waiter at a time, and only released by an explicit `release()`
    /// call. Used to serialize tests across suites that share the static stub state.
    actor StubLock {
        static let shared = StubLock()
        private var held = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            if !held {
                held = true
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            if let next = waiters.first {
                waiters.removeFirst()
                next.resume()  // hands lock directly to next waiter without flipping `held`
            } else {
                held = false
            }
        }
    }

    /// Run a test body with exclusive access to the static stub state.
    /// All tests that touch `StubURLProtocol` MUST wrap their body in this.
    static func withExclusiveStubs<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await StubLock.shared.acquire()
        do {
            responses.removeAll()
            captured.removeAll()
            let result = try await body()
            await StubLock.shared.release()
            return result
        } catch {
            await StubLock.shared.release()
            throw error
        }
    }

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
