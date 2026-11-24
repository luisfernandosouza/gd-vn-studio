//! Arquivos do projeto para o Project Manager (M6-01; Data Model §2, spec 09 §3).
//!
//! A interface (`src/project-manager/tauri-fs.ts`) só fala com o disco por estes comandos. Os caminhos
//! chegam absolutos, com `/` ou com o separador do sistema. A gravação é atômica (arquivo temporário na
//! mesma pasta e `rename`), para que um travamento no meio nunca deixe um JSON pela metade (Req §8).

use serde::Serialize;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

/// Uma entrada de pasta, sem recursão.
#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub is_dir: bool,
}

fn message(path: &Path, err: std::io::Error) -> String {
    format!("{}: {}", path.display(), err)
}

pub fn read_text(path: &Path) -> Result<String, String> {
    fs::read_to_string(path).map_err(|e| message(path, e))
}

pub fn write_text(path: &Path, contents: &str) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("{}: caminho sem pasta", path.display()))?;
    fs::create_dir_all(parent).map_err(|e| message(parent, e))?;
    let name = path
        .file_name()
        .ok_or_else(|| format!("{}: caminho sem nome de arquivo", path.display()))?
        .to_string_lossy();
    let tmp: PathBuf = parent.join(format!(".{}.{}.tmp", name, std::process::id()));
    let result = (|| {
        let mut file = fs::File::create(&tmp)?;
        file.write_all(contents.as_bytes())?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp, path)
    })();
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(message(path, e));
    }
    Ok(())
}

pub fn exists(path: &Path) -> bool {
    path.exists()
}

pub fn create_dir(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|e| message(path, e))
}

/// Lista a pasta em ordem de nome. Pasta inexistente é erro; quem chama confere antes com `exists`.
pub fn read_dir(path: &Path) -> Result<Vec<DirEntry>, String> {
    let mut entries = Vec::new();
    for entry in fs::read_dir(path).map_err(|e| message(path, e))? {
        let entry = entry.map_err(|e| message(path, e))?;
        let is_dir = entry
            .file_type()
            .map(|t| t.is_dir())
            .map_err(|e| message(&entry.path(), e))?;
        entries.push(DirEntry {
            name: entry.file_name().to_string_lossy().into_owned(),
            is_dir,
        });
    }
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(entries)
}

/// Apaga um arquivo (nunca uma pasta). Arquivo que já não existe não é erro.
pub fn remove_file(path: &Path) -> Result<(), String> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(message(path, e)),
    }
}

pub fn copy_file(from: &Path, to: &Path) -> Result<(), String> {
    if let Some(parent) = to.parent() {
        fs::create_dir_all(parent).map_err(|e| message(parent, e))?;
    }
    fs::copy(from, to).map(|_| ()).map_err(|e| message(from, e))
}

#[tauri::command]
pub fn pm_read_text(path: String) -> Result<String, String> {
    read_text(Path::new(&path))
}

#[tauri::command]
pub fn pm_write_text(path: String, contents: String) -> Result<(), String> {
    write_text(Path::new(&path), &contents)
}

#[tauri::command]
pub fn pm_exists(path: String) -> bool {
    exists(Path::new(&path))
}

#[tauri::command]
pub fn pm_create_dir(path: String) -> Result<(), String> {
    create_dir(Path::new(&path))
}

#[tauri::command]
pub fn pm_read_dir(path: String) -> Result<Vec<DirEntry>, String> {
    read_dir(Path::new(&path))
}

#[tauri::command]
pub fn pm_remove_file(path: String) -> Result<(), String> {
    remove_file(Path::new(&path))
}

#[tauri::command]
pub fn pm_copy_file(from: String, to: String) -> Result<(), String> {
    copy_file(Path::new(&from), Path::new(&to))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("vnstudio-pm-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn grava_cria_pastas_e_le_de_volta() {
        let dir = temp_dir("write");
        let file = dir.join("scenes/ch01/inicio.json");
        write_text(&file, "{\n  \"a\": \"ação\"\n}\n").unwrap();
        assert_eq!(read_text(&file).unwrap(), "{\n  \"a\": \"ação\"\n}\n");
        write_text(&file, "{}\n").unwrap();
        assert_eq!(read_text(&file).unwrap(), "{}\n");
        // nenhum temporário fica para trás
        let names: Vec<_> = read_dir(&dir.join("scenes/ch01"))
            .unwrap()
            .into_iter()
            .map(|e| e.name)
            .collect();
        assert_eq!(names, vec!["inicio.json"]);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn lista_em_ordem_e_marca_pastas() {
        let dir = temp_dir("list");
        create_dir(&dir.join("chapters")).unwrap();
        write_text(&dir.join("project.json"), "{}").unwrap();
        write_text(&dir.join("assets.json"), "{}").unwrap();
        assert_eq!(
            read_dir(&dir).unwrap(),
            vec![
                DirEntry {
                    name: "assets.json".into(),
                    is_dir: false
                },
                DirEntry {
                    name: "chapters".into(),
                    is_dir: true
                },
                DirEntry {
                    name: "project.json".into(),
                    is_dir: false
                },
            ]
        );
        assert!(read_dir(&dir.join("nada")).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn copia_e_apaga() {
        let dir = temp_dir("copy");
        write_text(&dir.join("project.json"), "{}").unwrap();
        copy_file(
            &dir.join("project.json"),
            &dir.join(".vnstudio/backups/x/project.json"),
        )
        .unwrap();
        assert!(exists(&dir.join(".vnstudio/backups/x/project.json")));
        remove_file(&dir.join("project.json")).unwrap();
        remove_file(&dir.join("project.json")).unwrap();
        assert!(!exists(&dir.join("project.json")));
        fs::remove_dir_all(&dir).unwrap();
    }
}
