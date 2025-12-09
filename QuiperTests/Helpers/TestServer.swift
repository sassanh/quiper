import Foundation

@MainActor
class TestServer {
    static let shared = TestServer()
    private var tempDir: URL?
    
    var baseURL: URL {
        guard let tempDir = tempDir else {
            // Fallback if not started
            return FileManager.default.temporaryDirectory.appendingPathComponent("index.html")
        }
        return tempDir.appendingPathComponent("index.html")
    }
    
    func start() throws {
        guard tempDir == nil else { return }
        
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuiperTestServer-\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir!, withIntermediateDirectories: true, attributes: nil)
        
        let indexHTML = """
        <html>
        <body>
            <textarea id="prompt-textarea"></textarea>
            <button id="new-chat-btn" onclick="document.getElementById('status').innerText = 'New Chat Started'">New Chat</button>
            <div id="status"></div>
            <a id="internal-link" href="subpage.html">Internal Link</a>
            <a id="external-link" href="https://example.com">External Link</a>
        </body>
        </html>
        """
        try indexHTML.write(to: tempDir!.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        
        let subpageHTML = "<html><body><h1>Subpage</h1></body></html>"
        try subpageHTML.write(to: tempDir!.appendingPathComponent("subpage.html"), atomically: true, encoding: .utf8)
    }
    
    func stop() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }
}
