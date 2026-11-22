//! Processo nativo do Studio (spec 09 §1): arquivos, Godot embutido e Git chegam em tarefas próprias.
//! Por enquanto só abre a janela principal e atende o teste de fumaça da CI.

mod smoke;

/// A interface chama este comando quando o React monta (`src/native.ts`).
#[tauri::command]
fn app_ready(app: tauri::AppHandle) {
    smoke::on_app_ready(&app);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    smoke::start_watchdog();
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![app_ready])
        .run(tauri::generate_context!())
        .expect("erro ao iniciar o Visual Novel Studio");
}
