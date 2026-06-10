import Foundation
import Network
import UIKit
import WebKit

enum IceVaultLaunchDestination: Equatable {
    case native
    case web(URL)
    case offline
}

enum IceVaultSignalGate {
    static let baseCheckURL = URL(string: "https://icevaultapp.top/g8kd5h")!
    static var checkURL: URL { baseCheckURL }

    private static let timeoutSeconds: TimeInterval = 6
    private static let maxRedirectCount = 12

    static func resolveDestination(checkURL: URL = Self.checkURL) async -> IceVaultLaunchDestination {
        guard await hasNetworkConnection() else {
            return .offline
        }

        do {
            let result = try await fetchFinalResponse(checkURL: checkURL)
            await syncCookies(from: result.responses, fallbackURL: checkURL)
            if (400...599).contains(result.finalResponse.statusCode) {
                return .native
            }
            return .web(checkURL)
        } catch {
            let stillHasNetwork = await hasNetworkConnection()
            if isOfflineError(error) || (isTimeoutError(error) && !stillHasNetwork) {
                return .offline
            }
            return .native
        }
    }

    private static func fetchFinalResponse(checkURL: URL) async throws -> IceVaultRedirectResult {
        try await withThrowingTaskGroup(of: IceVaultRedirectResult.self) { group in
            group.addTask {
                try await resolveRedirectChain(from: checkURL)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else { throw URLError(.unknown) }
            group.cancelAll()
            return result
        }
    }

    private static func resolveRedirectChain(from startURL: URL) async throws -> IceVaultRedirectResult {
        var currentURL = startURL
        var responses: [HTTPURLResponse] = []

        for _ in 0...maxRedirectCount {
            let response = try await fetchSingleResponse(url: currentURL)
            responses.append(response)

            guard
                (300...399).contains(response.statusCode),
                let location = response.value(forHTTPHeaderField: "Location"),
                let nextURL = URL(string: location, relativeTo: currentURL)?.absoluteURL
            else {
                return IceVaultRedirectResult(finalURL: response.url ?? currentURL, finalResponse: response, responses: responses)
            }
            currentURL = nextURL
        }

        throw URLError(.httpTooManyRedirects)
    }

    private static func fetchSingleResponse(url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue(nativeUserAgent, forHTTPHeaderField: "User-Agent")

        let delegate = IceVaultRedirectStoppingDelegate()
        let session = URLSession(configuration: gateSessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return httpResponse
    }

    private static var gateSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": nativeUserAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ",")
        ]
        return configuration
    }

    private static func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch URLError.Code(rawValue: nsError.code) {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    private static func isTimeoutError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && URLError.Code(rawValue: nsError.code) == .timedOut
    }

    private static func hasNetworkConnection() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "IceVault.SignalGate.NetworkPath")
            let state = IceVaultContinuationState()

            monitor.pathUpdateHandler = { path in
                if state.resumeOnce() {
                    monitor.cancel()
                    continuation.resume(returning: path.status == .satisfied)
                }
            }
            monitor.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.5) {
                if state.resumeOnce() {
                    monitor.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private static var nativeUserAgent: String {
        let appName = Bundle.main.bundleIdentifier ?? "IceVaultSlot"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let cfNetworkVersion = Bundle(identifier: "com.apple.CFNetwork")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1490.0.4"
        return "\(appName)/\(appVersion) CFNetwork/\(cfNetworkVersion) Darwin/\(darwinVersion)"
    }

    private static var darwinVersion: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.release)
        let version = mirror.children.compactMap { child -> String? in
            guard let value = child.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
        return version.isEmpty ? "23.0.0" : version
    }

    private static func syncCookies(from responses: [HTTPURLResponse], fallbackURL: URL) async {
        let cookieStore = await WKWebsiteDataStore.default().httpCookieStore
        var cookiesByName: [String: HTTPCookie] = [:]

        for response in responses {
            let responseURL = response.url ?? fallbackURL
            let headerCookies = HTTPCookie.cookies(
                withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:],
                for: responseURL
            )
            let storedCookies = HTTPCookieStorage.shared.cookies(for: responseURL) ?? []
            for cookie in headerCookies + storedCookies {
                cookiesByName["\(cookie.domain)|\(cookie.path)|\(cookie.name)"] = cookie
            }
        }

        for cookie in cookiesByName.values {
            await cookieStore.iceVaultSetCookieAsync(cookie)
        }
    }
}

private struct IceVaultRedirectResult {
    let finalURL: URL
    let finalResponse: HTTPURLResponse
    let responses: [HTTPURLResponse]
}

private final class IceVaultRedirectStoppingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class IceVaultContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

private extension WKHTTPCookieStore {
    func iceVaultSetCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}
