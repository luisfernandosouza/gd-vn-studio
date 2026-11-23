//! Bancada do spike M4-02 no webview do Tauri (WebView2, WKWebView, WebKitGTK).
//!
//! A janela faz o papel do Studio: abre o export Web do runtime num iframe servido por
//! `vnpreview` (src/vnpreview.rs), conversa com ele pela ponte do PP §1.1 e mede a abertura com
//! cada template, a montagem e a troca dos `.pck` de plugin, e a leitura de assets do projeto.
//!
//! Variáveis de ambiente:
//!   SPIKE_RUNTIME   pasta servida em /runtime/ (uma subpasta por template: official, lean)
//!   SPIKE_PROJECT   projeto aberto (assets/ e .vnstudio/preview/)
//!   SPIKE_OUT       onde gravar o JSON com os resultados
//!   SPIKE_RUNS      aberturas por template (padrão 5)
//!   SPIKE_TIMEOUT   segundos até desistir (padrão 300)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod vnpreview;

use std::{
    env, fs,
    path::PathBuf,
    process,
    sync::{Arc, RwLock},
    thread,
    time::Duration,
};

use serde_json::{json, Value};

struct Config {
    runtime: PathBuf,
    project: PathBuf,
    out: PathBuf,
    runs: u32,
}

fn config() -> Config {
    let path = |k: &str| PathBuf::from(env::var(k).unwrap_or_else(|_| panic!("falta {k}")));
    Config {
        runtime: path("SPIKE_RUNTIME"),
        project: path("SPIKE_PROJECT"),
        out: path("SPIKE_OUT"),
        runs: env::var("SPIKE_RUNS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(5),
    }
}

/// Origem do protocolo em cada sistema, como o Tauri 2 expõe protocolos próprios (PP §1.1).
fn origin() -> &'static str {
    if cfg!(windows) {
        "http://vnpreview.localhost"
    } else {
        "vnpreview://localhost"
    }
}

#[tauri::command]
fn spike_config(state: tauri::State<'_, Value>) -> Value {
    state.inner().clone()
}

#[tauri::command]
fn spike_report(app: tauri::AppHandle, state: tauri::State<'_, Value>, report: Value) {
    let out = PathBuf::from(state["out"].as_str().unwrap_or("spike-results.json"));
    let mut full = json!({
        "os": env::consts::OS,
        "arch": env::consts::ARCH,
        "origin": origin(),
    });
    full["report"] = report;
    fs::write(&out, serde_json::to_string_pretty(&full).unwrap()).expect("gravar resultados");
    println!("vnpreview-spike: resultados em {}", out.display());
    app.exit(0);
}

#[tauri::command]
fn spike_log(line: String) {
    println!("vnpreview-spike: {line}");
}

fn main() {
    let cfg = config();
    let timeout = env::var("SPIKE_TIMEOUT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(300);
    thread::spawn(move || {
        thread::sleep(Duration::from_secs(timeout));
        eprintln!("vnpreview-spike: sem resultado em {timeout} s");
        process::exit(2);
    });

    let templates: Vec<String> = fs::read_dir(&cfg.runtime)
        .expect("SPIKE_RUNTIME")
        .filter_map(|e| e.ok())
        .filter(|e| e.path().join("index.html").is_file())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    let expected = fs::read_to_string(cfg.project.join("expected.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .unwrap_or(Value::Null);
    let state = json!({
        "origin": origin(),
        "templates": templates,
        "runs": cfg.runs,
        "out": cfg.out,
        "expected": expected,
    });

    let roots: vnpreview::SharedRoots = Arc::new(RwLock::new(Some(vnpreview::Roots::for_project(
        &cfg.runtime,
        &cfg.project,
    ))));
    tauri::Builder::default()
        .manage(state)
        .register_asynchronous_uri_scheme_protocol("vnpreview", move |_ctx, request, responder| {
            let roots = roots.clone();
            thread::spawn(move || responder.respond(vnpreview::handle(&roots, &request)));
        })
        .invoke_handler(tauri::generate_handler![
            spike_config,
            spike_report,
            spike_log
        ])
        .run(tauri::generate_context!())
        .expect("erro ao abrir a bancada");
}
