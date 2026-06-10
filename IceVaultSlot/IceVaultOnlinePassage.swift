import SwiftUI
import UIKit
import WebKit

final class IceVaultWebNavigationController: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false

    private weak var webView: WKWebView?
    private var startURL: URL?

    func attach(_ webView: WKWebView, startURL: URL) {
        self.webView = webView
        self.startURL = startURL
        updateState()
    }

    func updateState() {
        canGoBack = previousAllowedItem() != nil
        canGoForward = webView?.canGoForward ?? false
    }

    func goBack() {
        guard let webView, let item = previousAllowedItem() else { return }
        webView.go(to: item)
        updateStateSoon()
    }

    func goForward() {
        guard let webView, webView.canGoForward else { return }
        webView.goForward()
        updateStateSoon()
    }

    private func updateStateSoon() {
        updateState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updateState()
        }
    }

    private func previousAllowedItem() -> WKBackForwardListItem? {
        guard let webView else { return nil }
        return webView.backForwardList.backList.reversed().first { item in
            !isStartURL(item.url)
        }
    }

    private func isStartURL(_ url: URL) -> Bool {
        guard let startURL else { return false }
        return normalizedURL(url) == normalizedURL(startURL)
    }

    private func normalizedURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        var normalized = components?.url?.absoluteString ?? url.absoluteString
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }
}

struct IceVaultOnlinePassage: View {
    let url: URL
    let onBlockedResponse: () -> Void

    @State private var isWebViewVisible = false
    @StateObject private var navigationController = IceVaultWebNavigationController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            IceVaultGateBrowser(
                url: url,
                onReady: { isWebViewVisible = true },
                onBlockedResponse: onBlockedResponse,
                onWebViewReady: { webView in
                    navigationController.attach(webView, startURL: url)
                },
                onNavigationStateChange: { _, _ in
                    navigationController.updateState()
                }
            )
            .background(Color.black)
            .opacity(isWebViewVisible ? 1 : 0)

            IceVaultWebNavigationOverlay(
                canGoBack: navigationController.canGoBack,
                canGoForward: navigationController.canGoForward,
                goBack: navigationController.goBack,
                goForward: navigationController.goForward
            )
            .opacity(isWebViewVisible ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            IceVaultOrientation.current = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
        .onDisappear {
            IceVaultOrientation.current = .portrait
        }
    }
}

struct IceVaultGateBrowser: UIViewRepresentable {
    let url: URL
    let onReady: () -> Void
    let onBlockedResponse: () -> Void
    let onWebViewReady: (WKWebView) -> Void
    let onNavigationStateChange: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReady: onReady,
            onBlockedResponse: onBlockedResponse,
            onNavigationStateChange: onNavigationStateChange
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = IceVaultWebUserAgent.safariLike
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.webView = webView
        onWebViewReady(webView)
        webView.load(IceVaultWebUserAgent.safariRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onReady: () -> Void
        let onBlockedResponse: () -> Void
        let onNavigationStateChange: (Bool, Bool) -> Void
        weak var webView: WKWebView?

        init(
            onReady: @escaping () -> Void,
            onBlockedResponse: @escaping () -> Void,
            onNavigationStateChange: @escaping (Bool, Bool) -> Void
        ) {
            self.onReady = onReady
            self.onBlockedResponse = onBlockedResponse
            self.onNavigationStateChange = onNavigationStateChange
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame == nil, ["http", "https"].contains(url.scheme?.lowercased()) {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme?.lowercased(), !["http", "https", "about"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse,
               (400...599).contains(response.statusCode) {
                decisionHandler(.cancel)
                DispatchQueue.main.async { [onBlockedResponse] in
                    onBlockedResponse()
                }
                return
            }

            if navigationResponse.isForMainFrame {
                DispatchQueue.main.async { [onReady] in
                    onReady()
                }
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let requestURL = navigationAction.request.url {
                webView.load(IceVaultWebUserAgent.safariRequest(url: requestURL))
            } else {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            self.webView?.goBack()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentWebDialog(
                title: webView.url?.host ?? "Message",
                message: message,
                actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }],
                fallback: completionHandler
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentWebDialog(
                title: webView.url?.host ?? "Confirm",
                message: message,
                actions: [
                    UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) },
                    UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }
                ],
                fallback: { completionHandler(false) }
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = UIAlertController(title: webView.url?.host ?? "Input", message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presentAlertController(alert, fallback: { completionHandler(nil) })
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.prompt)
        }

        private func updateNavigationState(_ webView: WKWebView) {
            DispatchQueue.main.async { [onNavigationStateChange] in
                onNavigationStateChange(webView.canGoBack, webView.canGoForward)
            }
        }

        private func presentWebDialog(
            title: String,
            message: String,
            actions: [UIAlertAction],
            fallback: @escaping () -> Void
        ) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach(alert.addAction)
            presentAlertController(alert, fallback: fallback)
        }

        private func presentAlertController(_ alert: UIAlertController, fallback: @escaping () -> Void) {
            DispatchQueue.main.async {
                guard let presenter = UIApplication.shared.iceVaultTopMostViewController() else {
                    fallback()
                    return
                }
                if presenter.presentedViewController == nil {
                    presenter.present(alert, animated: true)
                } else {
                    fallback()
                }
            }
        }
    }
}

struct IceVaultWebNavigationOverlay: View {
    var canGoBack: Bool
    var canGoForward: Bool
    var goBack: () -> Void
    var goForward: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    navButton(systemName: "chevron.left", enabled: canGoBack, action: goBack)
                    navButton(systemName: "chevron.right", enabled: canGoForward, action: goForward)
                }
                .padding(8)
                .background(Color.black.opacity(0.42), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.bottom, max(6, proxy.safeAreaInsets.bottom - 18))
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.28))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(enabled ? 0.14 : 0.06), in: Circle())
                .contentShape(Circle())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
    }
}

private enum IceVaultWebUserAgent {
    static var safariLike: String {
        let osVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let majorVersion = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "18"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(majorVersion).0 Mobile/15E148 Safari/604.1"
    }

    static func safariRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(safariLike, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ","), forHTTPHeaderField: "Accept-Language")
        return request
    }
}

private extension UIApplication {
    func iceVaultTopMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return iceVaultTopMostViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController {
            return iceVaultTopMostViewController(base: tabBarController.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return iceVaultTopMostViewController(base: presented)
        }
        return base
    }
}
