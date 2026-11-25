import Foundation

/// The page a failed navigation leaves behind. It commits at the address
/// that failed, so history, refresh, the location bar, and tab restore all
/// treat it like any other document; nothing outside this type needs to
/// know that the page is an error.
enum WebLoadErrorPage {
    /// The page for `error`. A page that stands for an address can be
    /// re-requested, so it offers Retry; a page with no address behind it —
    /// the one place a failure can land without one — has nothing to retry
    /// and offers nothing.
    static func html(for error: WebLoadError, address: URL?) -> String {
        let title = escape(error.kind.title)
        let message = escape(error.kind.message)
        let retryButton = address == nil
            ? ""
            : #"<button type="button" autofocus onclick="location.reload()">Retry</button>"#

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        html, body { height: 100%; margin: 0; }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 32px;
            background: #f5f5f7;
            color: #1d1d1f;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            -webkit-font-smoothing: antialiased;
        }
        main {
            display: flex;
            flex-direction: column;
            align-items: center;
            max-width: 380px;
            text-align: center;
        }
        svg { width: 32px; height: 32px; color: #8e8e93; }
        h1 { margin: 16px 0 0; font-size: 18px; font-weight: 600; line-height: 1.3; }
        p { margin: 8px 0 0; font-size: 13px; line-height: 1.45; color: #6e6e73; }
        button {
            margin-top: 20px;
            padding: 6px 18px;
            border: 1px solid rgba(0, 0, 0, 0.14);
            border-radius: 6px;
            background: #ffffff;
            color: #1d1d1f;
            font: inherit;
            font-size: 13px;
            cursor: pointer;
            -webkit-appearance: none;
            appearance: none;
        }
        button:hover { background: #f0f0f2; }
        button:active { background: #e5e5e7; }
        button:focus-visible { outline: 3px solid rgba(0, 122, 255, 0.5); outline-offset: 2px; }
        @media (prefers-color-scheme: dark) {
            body { background: #1e1e1e; color: #f5f5f7; }
            svg { color: #98989d; }
            p { color: #a1a1a6; }
            button { background: #2c2c2e; color: #f5f5f7; border-color: rgba(255, 255, 255, 0.14); }
            button:hover { background: #3a3a3c; }
            button:active { background: #48484a; }
        }
        </style>
        </head>
        <body>
        <main>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
            <path d="M12 3.5 2.8 19.5h18.4L12 3.5Z" stroke-linejoin="round"/>
            <path d="M12 9.5v4.5" stroke-linecap="round"/>
            <circle cx="12" cy="17" r="0.75" fill="currentColor" stroke="none"/>
        </svg>
        <h1>\(title)</h1>
        <p>\(message)</p>
        \(retryButton)
        </main>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
