import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let data: Data
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// 127.0.0.1의 자체 서명 인증서(Antigravity 로컬 서버)를 받아 주는 세션.
    static let localSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        return URLSession(configuration: config, delegate: LocalhostTrust(), delegateQueue: nil)
    }()

    static func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        json body: Any? = nil,
        form: [String: String]? = nil,
        session: URLSession = HTTP.session
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue(request.value(forHTTPHeaderField: "User-Agent") ?? "Mactatus/0.1", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            } catch let error as URLError where attempt == 0 && error.isTransient && session !== localSession {
                attempt += 1
                try? await Task.sleep(for: .seconds(2))
            } catch let error as URLError {
                throw UsageIssue.network(error.friendlyMessage(host: url.host() ?? "서버"))
            } catch {
                throw UsageIssue.network("\(url.host() ?? "서버")에 연결하지 못했어요.")
            }
        }
    }
}

extension URLError {
    /// 잠깐 기다렸다 다시 하면 될 만한 오류.
    var isTransient: Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost, .notConnectedToInternet]
            .contains(code)
    }

    func friendlyMessage(host: String) -> String {
        switch code {
        case .timedOut: "\(host) 응답이 늦어요(시간 초과)."
        case .notConnectedToInternet: "인터넷에 연결돼 있지 않아요."
        case .networkConnectionLost: "연결이 중간에 끊겼어요."
        case .cannotFindHost, .dnsLookupFailed: "\(host) 주소를 찾지 못했어요."
        default: "\(host)에 연결하지 못했어요(\(code.rawValue))."
        }
    }
}

final class LocalhostTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        guard challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
