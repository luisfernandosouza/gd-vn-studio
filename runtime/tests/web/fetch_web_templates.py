#!/usr/bin/env python3
"""Baixa só os templates Web do pacote oficial de templates do Godot (tarefa M4-03).

O `.tpz` da release tem ~1,3 GB; os templates Web sem threads são uns 40 MB. Este script lê o
diretório central do zip por requisições HTTP Range e baixa só os membros pedidos, gravando-os na
pasta de templates do Godot (`~/.local/share/godot/export_templates/<versão>/`, ou `--dest`).

Uso: python3 runtime/tests/web/fetch_web_templates.py 4.7.2-stable [--dest DIR] [membro ...]
Sem membros, baixa `web_nothreads_debug.zip`, `web_nothreads_release.zip` e `version.txt`.
"""
import argparse
import io
import os
import pathlib
import sys
import urllib.request
import zipfile

DEFAULT_MEMBERS = ["web_nothreads_debug.zip", "web_nothreads_release.zip", "version.txt"]


class HttpRangeFile(io.IOBase):
    """Arquivo somente leitura com seek, apoiado em requisições HTTP Range (lê adiante em blocos de 8 MB)."""

    CHUNK = 8 << 20

    def __init__(self, url: str):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r:
            self.url = r.geturl()  # segue o redirecionamento da release uma vez só
            self.size = int(r.headers["Content-Length"])
        self.pos = 0
        self.buf_start = 0
        self.buf = b""

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence]
        self.pos = base + offset
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        if n <= 0:
            return b""
        off = self.pos - self.buf_start
        if not (0 <= off and off + n <= len(self.buf)):
            self.buf_start = self.pos
            self.buf = self._fetch(self.pos, min(max(n, self.CHUNK), self.size - self.pos))
            off = 0
        data = self.buf[off:off + n]
        self.pos += len(data)
        return data

    def _fetch(self, start: int, n: int) -> bytes:
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{start + n - 1}"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req) as r:
                    if r.status != 206:
                        raise OSError(f"o servidor não aceitou Range (HTTP {r.status})")
                    return r.read()
            except OSError:
                if attempt == 3:
                    raise
        raise AssertionError("inalcançável")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("version", help="versão do Godot, como 4.7.2-stable")
    ap.add_argument("members", nargs="*", default=DEFAULT_MEMBERS)
    ap.add_argument("--dest", help="pasta de destino (padrão: a de templates do Godot)")
    args = ap.parse_args()

    url = (f"https://github.com/godotengine/godot/releases/download/{args.version}/"
           f"Godot_v{args.version}_export_templates.tpz")
    dest = pathlib.Path(args.dest) if args.dest else (
        pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share"))
        / "godot/export_templates" / args.version.replace("-", "."))
    dest.mkdir(parents=True, exist_ok=True)

    raw = HttpRangeFile(url)
    with zipfile.ZipFile(raw) as z:
        names = {pathlib.PurePosixPath(n).name: n for n in z.namelist()}
        for m in args.members:
            if m not in names:
                print(f"fetch_web_templates: {m} não está em {url}", file=sys.stderr)
                return 1
            out = dest / m
            with z.open(names[m]) as src, open(out, "wb") as dst:
                while chunk := src.read(1 << 20):
                    dst.write(chunk)
            print(f"{out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
