import SwiftUI
import WebKit

struct InAppAuthSheet: View {
    let kind: AccountKind
    let onCookieCaptured: (String) -> Void
    let onCancel: () -> Void

    @State private var status: String = "Sign in to claude.ai. We'll auto-capture your sessionKey."

    private var dataStore: WKWebsiteDataStore {
        switch kind {
        case .personal:
            return .default()
        case .work:
            return .nonPersistent()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(kind == .personal ? "Connect Personal" : "Connect Work")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
            }
            .padding(12)

            Divider()

            AuthWebView(
                dataStore: dataStore,
                onStatus: { status = $0 },
                onCookieCaptured: { cookie in
                    onCookieCaptured(cookie)
                }
            )

            Divider()

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(width: 760, height: 620)
    }
}

private struct AuthWebView: NSViewRepresentable {
    let dataStore: WKWebsiteDataStore
    let onStatus: (String) -> Void
    let onCookieCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dataStore: dataStore, onStatus: onStatus, onCookieCaptured: onCookieCaptured)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore

        let view = WKWebView(frame: .zero, configuration: cfg)
        view.navigationDelegate = context.coordinator
        context.coordinator.prepareAndLoad(view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let dataStore: WKWebsiteDataStore
        private let onStatus: (String) -> Void
        private let onCookieCaptured: (String) -> Void
        private var didCapture = false
        private var pollTimer: Timer?
        private var pollAttempts = 0

        init(dataStore: WKWebsiteDataStore,
             onStatus: @escaping (String) -> Void,
             onCookieCaptured: @escaping (String) -> Void) {
            self.dataStore = dataStore
            self.onStatus = onStatus
            self.onCookieCaptured = onCookieCaptured
        }

        deinit {
            stopObserving()
        }

        func prepareAndLoad(_ webView: WKWebView) {
            onStatus("Preparing clean login session…")

            dataStore.httpCookieStore.add(self)
            startCookiePolling()

            let loginURL = URL(string: "https://claude.ai/login")!

            dataStore.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
                guard let self, let webView else { return }

                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                let group = DispatchGroup()

                for cookie in claudeCookies {
                    group.enter()
                    self.dataStore.httpCookieStore.delete(cookie) { group.leave() }
                }

                group.notify(queue: .main) {
                    self.onStatus("Loading claude.ai login…")
                    webView.load(URLRequest(url: loginURL))
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didCapture else { return }
            checkForSessionKey()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatus("Login page failed to load: \(error.localizedDescription)")
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !didCapture else { return }
            checkForSessionKey()
        }

        private func startCookiePolling() {
            pollTimer?.invalidate()
            pollAttempts = 0
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if self.didCapture {
                    timer.invalidate()
                    return
                }
                self.pollAttempts += 1
                self.checkForSessionKey()
                if self.pollAttempts >= 90 {
                    timer.invalidate()
                    self.onStatus("No sessionKey detected yet. If login succeeded, click Save and paste manually as fallback.")
                }
            }
            if let pollTimer {
                RunLoop.main.add(pollTimer, forMode: .common)
            }
        }

        private func stopObserving() {
            pollTimer?.invalidate()
            pollTimer = nil
            dataStore.httpCookieStore.remove(self)
        }

        private func checkForSessionKey() {
            dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                if let session = cookies.first(where: {
                    $0.name == "sessionKey" && $0.domain.contains("claude.ai") && !$0.value.isEmpty
                }) {
                    self.didCapture = true
                    self.stopObserving()
                    self.onStatus("Captured sessionKey. Saving…")
                    self.onCookieCaptured(session.value)
                    return
                }

                let claudeCookieNames = cookies
                    .filter { $0.domain.contains("claude.ai") }
                    .map { $0.name }
                if !claudeCookieNames.isEmpty {
                    let names = Array(Set(claudeCookieNames)).sorted().joined(separator: ", ")
                    self.onStatus("Signed in? Waiting for sessionKey. Seen cookies: \(names)")
                } else {
                    self.onStatus("Waiting for claude.ai cookies…")
                }
            }
        }
    }
}
