#!/usr/bin/python3.12
"""Roda a bancada no WebKitGTK, o motor do Tauri no Linux (webkit2gtk-4.1).

Abre harness/index.html?autorun=1 numa WebView do WebKitGTK e espera a página
gravar build/work/results-webkitgtk.json. Precisa de python3-gi,
gir1.2-webkit2-4.1 e, sem tela, de Xvfb (xvfb-run).

Uso: xvfb-run -a -s "-screen 0 1920x1080x24" tools/webkitgtk_bench.py [porta] [edições] [parâmetros extras da página]
Teste B dos assets: parâmetro extra "&suite=assets" (e antes, tools/make_assets.py).
"""
import os, subprocess, sys, time
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import GLib, Gtk, WebKit2  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
edits = int(sys.argv[2]) if len(sys.argv) > 2 else 20
extra = sys.argv[3] if len(sys.argv) > 3 else ""  # ex.: "&only=open&templates=web-lean"
out = ROOT / "build" / "work" / "results-webkitgtk.json"
out.unlink(missing_ok=True)

server = subprocess.Popen(["node", str(ROOT / "tools" / "serve.mjs"), str(port), "--cache", "--rss", "^WebKit"])
time.sleep(1)

settings = WebKit2.Settings()
settings.set_enable_webgl(True)
settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.ALWAYS)
settings.set_enable_write_console_messages_to_stdout(True)
settings.set_media_playback_requires_user_gesture(False)
view = WebKit2.WebView.new_with_context(WebKit2.WebContext.new_ephemeral())
view.set_settings(settings)
win = Gtk.Window()
win.set_default_size(1300, 900)
win.add(view)
win.show_all()
view.load_uri(f"http://127.0.0.1:{port}/harness/index.html?autorun=1&engine=webkitgtk&edits={edits}{extra}")

start = time.time()


def check():
    if out.exists() or time.time() - start > 2400:
        Gtk.main_quit()
        return False
    return True


GLib.timeout_add(1000, check)
Gtk.main()
server.terminate()
print(f"WebKitGTK {WebKit2.get_major_version()}.{WebKit2.get_minor_version()}.{WebKit2.get_micro_version()}")
print(out.read_text() if out.exists() else "sem resultado (tempo esgotado)")
