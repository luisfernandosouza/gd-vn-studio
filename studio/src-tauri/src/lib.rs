//! Processo nativo do Studio (spec 09 §1): arquivos, Godot embutido e Git chegam em tarefas próprias.
//! Por enquanto abre a janela principal, atende o teste de fumaça da CI e dá ao Project Manager
//! acesso aos arquivos do projeto (`project_fs`, M6-01) e serve o painel do Preview pelo protocolo
//! `vnpreview` (`vnpreview`, M6-10).

mod project_fs;
mod smoke;
mod vnpreview;

use std::{
    env,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
    thread,
};

use tauri::Manager;

/// A interface chama este comando quando o React monta (`src/native.ts`).
#[tauri::command]
fn app_ready(app: tauri::AppHandle) {
    smoke::on_app_ready(&app);
}

/// Pasta do export Web do runtime para o Preview, embutido no Studio (spec 09 §1). Em desenvolvimento,
/// `VNSTUDIO_PREVIEW_RUNTIME` aponta outra pasta. Pasta ausente só faz o `/runtime/…` dar 404: o painel
/// cai no dublê até o M6-14 trazer o runtime real.
fn preview_runtime_dir(app: &tauri::AppHandle) -> PathBuf {
    if let Some(dir) = env::var_os("VNSTUDIO_PREVIEW_RUNTIME") {
        return PathBuf::from(dir);
    }
    app.path()
        .resource_dir()
        .map(|dir| dir.join("runtime-preview"))
        .unwrap_or_else(|_| PathBuf::from("runtime-preview"))
}

/// O export Web do runtime está embutido? Sem ele (até o M6-14), o painel usa o dublê do runtime.
#[tauri::command]
fn preview_runtime_available(app: tauri::AppHandle) -> bool {
    preview_runtime_dir(&app).join("index.html").is_file()
}

/// O Studio troca o mapa do `vnpreview` ao abrir um projeto (PP §1.1).
#[tauri::command]
fn preview_open_project(
    app: tauri::AppHandle,
    roots: tauri::State<'_, vnpreview::SharedRoots>,
    root: String,
) -> Result<(), String> {
    let project = Path::new(&root);
    if !project.join("project.json").is_file() {
        return Err(format!("{root} não é a pasta de um projeto"));
    }
    let map = vnpreview::Roots::for_project(&preview_runtime_dir(&app), project);
    vnpreview::set_roots(&roots, Some(map));
    Ok(())
}

/// Fecha o mapa: sem projeto aberto, o `vnpreview` dá 404 em tudo.
#[tauri::command]
fn preview_close_project(roots: tauri::State<'_, vnpreview::SharedRoots>) {
    vnpreview::set_roots(&roots, None);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    smoke::start_watchdog();
    let roots: vnpreview::SharedRoots = Arc::new(RwLock::new(None));
    let for_protocol = roots.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(roots)
        .register_asynchronous_uri_scheme_protocol("vnpreview", move |_ctx, request, responder| {
            // Leitura de arquivo fora da thread da interface.
            let roots = for_protocol.clone();
            thread::spawn(move || responder.respond(vnpreview::handle(&roots, &request)));
        })
        .invoke_handler(tauri::generate_handler![
            app_ready,
            preview_runtime_available,
            preview_open_project,
            preview_close_project,
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
