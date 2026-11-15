// Roda a bancada numa WKWebView, o motor do Tauri no macOS.
// Abre harness/index.html?autorun=1 e espera a página gravar build/work/results-wkwebview.json.
// Uso: swift tools/wkwebview_bench.swift <porta> <edições>   (com tools/serve.mjs já rodando nessa porta)
import AppKit
import WebKit

let args = CommandLine.arguments
let port = args.count > 1 ? args[1] : "8767"
let edits = args.count > 2 ? args[2] : "20"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("build/work/results-wkwebview.json")
try? FileManager.default.removeItem(at: out)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
let view = WKWebView(frame: window.contentView!.bounds, configuration: config)
window.contentView!.addSubview(view)
window.makeKeyAndOrderFront(nil)
view.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/harness/index.html?autorun=1&engine=wkwebview&edits=\(edits)")!))

let start = Date()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    if FileManager.default.fileExists(atPath: out.path) || Date().timeIntervalSince(start) > 1500 {
        if let data = try? String(contentsOf: out, encoding: .utf8) { print(data) } else { print("sem resultado (tempo esgotado)") }
        exit(0)
    }
}
app.activate(ignoringOtherApps: true)
app.run()
