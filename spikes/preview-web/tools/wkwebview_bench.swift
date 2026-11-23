// Roda a bancada numa WKWebView, o motor do Tauri no macOS.
// Abre harness/index.html?autorun=1 e espera a página gravar build/work/results-wkwebview.json.
// A cada 20 s imprime o estado da página (carregou? o que a bancada já registrou?), para
// diagnosticar travamentos.
// Uso: swift tools/wkwebview_bench.swift <porta> <edições> [parâmetros extras, ex. "&skip=restart"]
//      Teste B dos assets: parâmetros extras "&suite=assets" (servidor com --rss WebKit)
//      (com tools/serve.mjs já rodando nessa porta)
import AppKit
import WebKit

let args = CommandLine.arguments
let port = args.count > 1 ? args[1] : "8767"
let edits = args.count > 2 ? args[2] : "20"
let extra = args.count > 3 ? args[3] : ""
let limit: TimeInterval = 2400
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("build/work/results-wkwebview.json")
try? FileManager.default.removeItem(at: out)

func log(_ s: String) {
    FileHandle.standardError.write(("[wkwebview] " + s + "\n").data(using: .utf8)!)
}

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { log("página carregada: \(w.url?.absoluteString ?? "?")") }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { log("falha: \(e)") }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { log("falha ao abrir: \(e)") }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { log("processo da página morreu") }
}

// Sem App Nap nem redução de timers: a página precisa de requestAnimationFrame rodando.
let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled, .latencyCritical], reason: "bancada")
_ = activity

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
config.mediaTypesRequiringUserActionForPlayback = []
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
window.level = .floating
let view = WKWebView(frame: window.contentView!.bounds, configuration: config)
let nav = Nav()
view.navigationDelegate = nav
if #available(macOS 13.3, *) { view.isInspectable = true }
window.contentView!.addSubview(view)
window.orderFrontRegardless()
let url = "http://127.0.0.1:\(port)/harness/index.html?autorun=1&engine=wkwebview&edits=\(edits)\(extra)"
log("abrindo \(url)")
view.load(URLRequest(url: URL(string: url)!))

let start = Date()
var tick = 0
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    tick += 1
    if FileManager.default.fileExists(atPath: out.path) || Date().timeIntervalSince(start) > limit {
        if let data = try? String(contentsOf: out, encoding: .utf8) { print(data) } else { print("{\"engine\":\"wkwebview\",\"error\":\"sem resultado (tempo esgotado)\"}") }
        exit(0)
    }
    if tick % 20 == 0 {
        let js = "JSON.stringify({bench: typeof bench, frame: !!(document.getElementById('frame')||{}).contentWindow, api: !!(document.getElementById('frame').contentWindow||{}).vnPreview, log: document.getElementById('log').textContent.slice(-400)})"
        view.evaluateJavaScript(js) { r, e in log("\(tick)s: \(r ?? e ?? "nada")") }
    }
}
app.activate(ignoringOtherApps: true)
app.run()
