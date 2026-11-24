//! Processo nativo do Studio (spec 09 §1): arquivos, Godot embutido e Git chegam em tarefas próprias.
//! Por enquanto abre a janela principal, atende o teste de fumaça da CI e dá ao Project Manager
//! acesso aos arquivos do projeto (`project_fs`, M6-01).

mod project_fs;
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
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            app_ready,
            project_fs::pm_read_text,
            project_fs::pm_write_text,
            project_fs::pm_exists,
            project_fs::pm_create_dir,
            project_fs::pm_read_dir,
            project_fs::pm_remove_file,
            project_fs::pm_copy_file
        ])
        .run(tauri::generate_context!())
        .expect("erro ao iniciar o Visual Novel Studio");
}
