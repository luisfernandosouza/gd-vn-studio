//! Protocolo `vnpreview` (PP §1.1): serve só o projeto aberto, por um mapa fixo de três prefixos.
//!
//! | Caminho              | Pasta                                   |
//! |----------------------|-----------------------------------------|
//! | `/runtime/…`         | export Web do runtime, embutido         |
//! | `/project/assets/…`  | `assets/` do projeto aberto             |
//! | `/project/preview/…` | `.vnstudio/preview/` do projeto aberto  |
//!
//! Qualquer outro caminho dá 404, inclusive caminhos absolutos do disco. Cada segmento é
//! decodificado (RFC 3986, UTF-8) e recusado se for `.`, `..`, vazio ou tiver separador, `:` ou
//! NUL; depois de resolver links, o arquivo precisa continuar dentro da pasta do prefixo.

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
};

use percent_encoding::percent_decode_str;
use tauri::http::{header, Method, Request, Response, StatusCode};

/// Mapa do projeto aberto. O Studio troca o mapa ao trocar de projeto.
#[derive(Clone, Debug)]
pub struct Roots {
    pub runtime: PathBuf,
    pub assets: PathBuf,
    pub preview: PathBuf,
}

impl Roots {
    pub fn for_project(runtime: &Path, project: &Path) -> Self {
        Self {
            runtime: runtime.to_path_buf(),
            assets: project.join("assets"),
            preview: project.join(".vnstudio").join("preview"),
        }
    }
}

pub type SharedRoots = Arc<RwLock<Option<Roots>>>;

/// Resolve o caminho da URL (ainda codificado) para um arquivo dentro de uma das três pastas.
pub fn resolve(roots: &Roots, url_path: &str) -> Option<PathBuf> {
    let (root, rest) = [
        ("/runtime/", &roots.runtime),
        ("/project/assets/", &roots.assets),
        ("/project/preview/", &roots.preview),
    ]
    .into_iter()
    .find_map(|(prefix, root)| url_path.strip_prefix(prefix).map(|rest| (root, rest)))?;
    let mut rel = PathBuf::new();
    for raw in rest.split('/') {
        let seg = percent_decode_str(raw).decode_utf8().ok()?;
        if seg.is_empty() || seg == "." || seg == ".." || seg.contains(['/', '\\', ':', '\0']) {
            return None;
        }
        rel.push(seg.as_ref());
    }
    let root = root.canonicalize().ok()?;
    // canonicalize resolve links: um link dentro de assets/ que aponta para fora é recusado.
    let file = root.join(rel).canonicalize().ok()?;
    if !file.starts_with(&root) || !file.is_file() {
        return None;
    }
    Some(file)
}

pub fn content_type(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .as_deref()
    {
        Some("wasm") => "application/wasm",
        Some("js") => "text/javascript; charset=utf-8",
        Some("html") => "text/html; charset=utf-8",
        Some("json") => "application/json",
        Some("txt") => "text/plain; charset=utf-8",
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("ogg") => "audio/ogg",
        Some("mp3") => "audio/mpeg",
        Some("wav") => "audio/wav",
        _ => "application/octet-stream",
    }
}

fn status(code: StatusCode) -> Response<Vec<u8>> {
    Response::builder()
        .status(code)
        .header(header::CONTENT_TYPE, "text/plain; charset=utf-8")
        .body(code.canonical_reason().unwrap_or("").as_bytes().to_vec())
        .expect("resposta de status")
}

pub fn handle(roots: &SharedRoots, request: &Request<Vec<u8>>) -> Response<Vec<u8>> {
    if request.method() != Method::GET && request.method() != Method::HEAD {
        return status(StatusCode::METHOD_NOT_ALLOWED);
    }
    let guard = roots.read().expect("mapa do vnpreview");
    let Some(roots) = guard.as_ref() else {
        return status(StatusCode::NOT_FOUND);
    };
    let Some(file) = resolve(roots, request.uri().path()) else {
        return status(StatusCode::NOT_FOUND);
    };
    match fs::read(&file) {
        Ok(bytes) => Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_TYPE, content_type(&file))
            .header(header::CACHE_CONTROL, "no-cache")
            .body(if request.method() == Method::HEAD {
                Vec::new()
            } else {
                bytes
            })
            .expect("resposta"),
        Err(_) => status(StatusCode::NOT_FOUND),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    struct Fixture {
        base: PathBuf,
        roots: Roots,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.base);
        }
    }

    fn fixture(name: &str) -> Fixture {
        let base = env::temp_dir().join(format!("vnpreview-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let runtime = base.join("runtime");
        let project = base.join("project");
        fs::create_dir_all(runtime.join("official")).unwrap();
        fs::create_dir_all(project.join("assets").join("música de teste")).unwrap();
        fs::create_dir_all(project.join(".vnstudio/preview/plugins")).unwrap();
        fs::write(runtime.join("official/index.wasm"), b"\0asm").unwrap();
        fs::write(project.join("assets/música de teste/olá mundo.txt"), b"oi").unwrap();
        fs::write(
            project.join(".vnstudio/preview/plugins/fishing.pck"),
            b"GDPC",
        )
        .unwrap();
        fs::write(project.join("segredo.txt"), b"fora do mapa").unwrap();
        fs::write(base.join("fora.txt"), b"fora do projeto").unwrap();
        let roots = Roots::for_project(&runtime, &project);
        Fixture { base, roots }
    }

    #[test]
    fn serve_os_tres_prefixos() {
        let f = fixture("prefixos");
        assert!(resolve(&f.roots, "/runtime/official/index.wasm").is_some());
        assert!(resolve(
            &f.roots,
            "/project/assets/m%C3%BAsica%20de%20teste/ol%C3%A1%20mundo.txt"
        )
        .is_some());
        assert!(resolve(&f.roots, "/project/preview/plugins/fishing.pck").is_some());
    }

    #[test]
    fn recusa_o_que_esta_fora_do_mapa() {
        let f = fixture("fora");
        for p in [
            "/",
            "/segredo.txt",
            "/project/segredo.txt",
            "/project/assets/",
            "/project/assets/%2e%2e/segredo.txt",
            "/project/assets/..%2fsegredo.txt",
            "/project/assets/..%5csegredo.txt",
            "/project/assets/../segredo.txt",
            "/project/assets/./m%C3%BAsica%20de%20teste/ol%C3%A1%20mundo.txt",
            "/project/assets//segredo.txt",
            "/project/preview/%2e%2e/%2e%2e/segredo.txt",
            "/runtime/%2e%2e/%2e%2e/fora.txt",
            "/runtime/C:%5cWindows%5cwin.ini",
            "/runtime/%00",
            "/etc/passwd",
            "//etc/passwd",
        ] {
            assert!(resolve(&f.roots, p).is_none(), "deveria recusar {p}");
        }
        let abs = f.base.join("fora.txt");
        let encoded = percent_encoding::utf8_percent_encode(
            abs.to_str().unwrap(),
            percent_encoding::NON_ALPHANUMERIC,
        )
        .to_string();
        assert!(resolve(&f.roots, &format!("/runtime/{encoded}")).is_none());
        assert!(resolve(&f.roots, &format!("/project/assets/{encoded}")).is_none());
    }

    #[cfg(unix)]
    #[test]
    fn recusa_link_que_sai_da_pasta() {
        let f = fixture("link");
        std::os::unix::fs::symlink(f.base.join("fora.txt"), f.roots.assets.join("link.txt"))
            .unwrap();
        assert!(resolve(&f.roots, "/project/assets/link.txt").is_none());
    }

    #[test]
    fn wasm_com_application_wasm() {
        assert_eq!(content_type(Path::new("a/index.wasm")), "application/wasm");
        assert_eq!(
            content_type(Path::new("a/x.pck")),
            "application/octet-stream"
        );
    }

    #[test]
    fn so_get_e_head_e_404_sem_projeto() {
        let f = fixture("metodo");
        let shared: SharedRoots = Arc::new(RwLock::new(Some(f.roots.clone())));
        let post = Request::builder()
            .method(Method::POST)
            .uri("vnpreview://localhost/runtime/official/index.wasm")
            .body(Vec::new())
            .unwrap();
        assert_eq!(
            handle(&shared, &post).status(),
            StatusCode::METHOD_NOT_ALLOWED
        );
        let get = Request::builder()
            .uri("vnpreview://localhost/runtime/official/index.wasm")
            .body(Vec::new())
            .unwrap();
        let res = handle(&shared, &get);
        assert_eq!(res.status(), StatusCode::OK);
        assert_eq!(res.headers()[header::CONTENT_TYPE], "application/wasm");
        let win = Request::builder()
            .uri("http://vnpreview.localhost/project/preview/plugins/fishing.pck")
            .body(Vec::new())
            .unwrap();
        assert_eq!(handle(&shared, &win).status(), StatusCode::OK);
        *shared.write().unwrap() = None;
        assert_eq!(handle(&shared, &get).status(), StatusCode::NOT_FOUND);
    }
}
