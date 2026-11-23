#!/usr/bin/env python3
"""Monta o projeto de teste que a bancada do Tauri abre (SPIKE_PROJECT).

  prepare_project.py <pasta dos .pck> <saída>

<saída>/project/assets/música de teste/olá mundo.txt   asset com acento e espaço no caminho
<saída>/project/.vnstudio/preview/plugins/*.pck          pacotes dos plugins
<saída>/project/segredo.txt e <saída>/fora.txt           o que o protocolo NÃO pode servir
<saída>/project/expected.json                            o que a bancada confere
"""

import hashlib
import json
import shutil
import sys
from pathlib import Path

pcks, out = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
project = out / "project"
shutil.rmtree(out, ignore_errors=True)
asset = project / "assets" / "música de teste" / "olá mundo.txt"
asset.parent.mkdir(parents=True)
data = ("Olá, mundo! Asset de teste do spike M4-02.\n" * 2000).encode()
asset.write_bytes(data)
plugins = project / ".vnstudio" / "preview" / "plugins"
plugins.mkdir(parents=True)
for p in pcks.glob("*.pck"):
    shutil.copy2(p, plugins / p.name)
(project / "segredo.txt").write_text("fora do mapa do protocolo\n")
(out / "fora.txt").write_text("fora do projeto\n")
(project / "expected.json").write_text(json.dumps({
    "asset_sha256": hashlib.sha256(data).hexdigest(),
    "outside_abs": str(out / "fora.txt"),
}))
print(project)
