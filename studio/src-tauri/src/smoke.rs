//! Teste de fumaça da CI: com `VNSTUDIO_SMOKE_TEST=1`, o app abre a janela, espera a
//! interface React avisar que montou (`app_ready`) e sai com código 0. Se a interface não
//! avisar dentro do prazo, sai com código 2, e a CI falha.

use std::{env, process, thread, time::Duration};

const ENV_VAR: &str = "VNSTUDIO_SMOKE_TEST";
const DEFAULT_TIMEOUT_SECS: u64 = 90;

pub fn enabled() -> bool {
    env::var(ENV_VAR).is_ok_and(|v| v == "1")
}

fn timeout() -> Duration {
    let secs = env::var("VNSTUDIO_SMOKE_TIMEOUT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(DEFAULT_TIMEOUT_SECS);
    Duration::from_secs(secs)
}

/// No modo de fumaça, encerra o processo com erro se a interface não montar a tempo.
pub fn start_watchdog() {
    if !enabled() {
        return;
    }
    let limit = timeout();
    thread::spawn(move || {
        thread::sleep(limit);
        eprintln!("vnstudio-smoke: a interface não avisou que montou em {limit:?}");
        process::exit(2);
    });
}

pub fn on_app_ready(app: &tauri::AppHandle) {
    if !enabled() {
        return;
    }
    println!("vnstudio-smoke: janela aberta e interface montada");
    app.exit(0);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desligado_sem_a_variavel() {
        env::remove_var(ENV_VAR);
        assert!(!enabled());
    }
}
