#!/usr/bin/env python3
"""Testes de protocolo do servidor do Preview contra preview-protocol.schema.json (tarefa M4-04).

Duas partes:

1. ``--transcript <arquivo.jsonl>``: valida as mensagens que ``test_preview_server.gd`` gravou nos dois
   transportes (painel e janela). Toda mensagem que o runtime mandou precisa valer pelo schema; cada
   resposta de sucesso é validada também contra ``$defs/<Método>_result``, e a requisição que a
   originou contra o schema das requisições.
2. ``--godot <binário>``: teste de ponta a ponta da janela (PP §1.2). Abre o runtime com
   ``--vn-preview-port``/``--vn-preview-token`` (``preview_host.gd``), conversa por WebSocket de
   verdade, valida cada mensagem e confere 4401, 4409 e que o processo sai sozinho em 10 s quando a
   conexão cai.

    python3 runtime/tests/preview/check_protocol.py --transcript /tmp/preview.jsonl --godot godot

Precisa de ``jsonschema>=4.18`` e ``websockets``.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import secrets
import socket
import subprocess
import sys
import time
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[3]
SCHEMAS = ROOT / "docs" / "specs" / "schemas"
RUNTIME = ROOT / "runtime"

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)
    print(f"FALHOU  {msg}")


def load_validators():
    resources = []
    for path in SCHEMAS.glob("*.schema.json"):
        doc = json.loads(path.read_text(encoding="utf-8"))
        res = Resource.from_contents(doc)
        resources.append((path.name, res))
        if "$id" in doc:
            resources.append((doc["$id"], res))
    registry = Registry().with_resources(resources)
    schema = json.loads((SCHEMAS / "preview-protocol.schema.json").read_text(encoding="utf-8"))
    base = schema.get("$id", "preview-protocol.schema.json")
    whole = Draft202012Validator(schema, registry=registry)
    requests = Draft202012Validator({"$ref": f"{base}#/oneOf/0"}, registry=registry)

    def result_validator(method: str):
        name = method[0].upper() + method[1:].replace(".", "_") + "_result"
        if name not in schema["$defs"]:
            return None
        return Draft202012Validator({"$ref": f"{base}#/$defs/{name}"}, registry=registry)

    return whole, requests, result_validator


def errors_of(validator, msg) -> list[str]:
    return [f"{'/'.join(map(str, e.absolute_path)) or '(raiz)'}: {e.message}" for e in validator.iter_errors(msg)]


class Checker:
    """Valida um fluxo de mensagens de um transporte, casando respostas com requisições pelo id."""

    def __init__(self, label: str):
        self.label = label
        self.whole, self.requests, self.result_validator = VALIDATORS
        self.pending: dict = {}
        self.count = 0
        self.results = 0

    def incoming(self, text: str) -> None:
        try:
            msg = json.loads(text)
        except ValueError:
            return
        if isinstance(msg, dict) and isinstance(msg.get("id"), (int, str)) and isinstance(msg.get("method"), str):
            self.pending[msg["id"]] = msg

    def outgoing(self, text: str) -> dict:
        self.count += 1
        msg = json.loads(text)
        errs = errors_of(self.whole, msg)
        if errs:
            fail(f"{self.label}: mensagem do runtime fora do schema: {text}\n        " + "\n        ".join(errs[:5]))
            return msg
        if "id" in msg and "result" in msg:
            req = self.pending.get(msg["id"])
            if req is None:
                fail(f"{self.label}: resposta sem requisição: {text}")
                return msg
            req_errs = errors_of(self.requests, req)
            if req_errs:
                fail(f"{self.label}: requisição aceita fora do schema: {json.dumps(req)}\n        " + "\n        ".join(req_errs[:5]))
            validator = self.result_validator(req["method"])
            if validator is not None:
                self.results += 1
                res_errs = errors_of(validator, msg["result"])
                if res_errs:
                    fail(f"{self.label}: resultado de {req['method']} fora do schema: {text}\n        " + "\n        ".join(res_errs[:5]))
        if "id" in msg and msg["id"] is not None and ("result" in msg or "error" in msg):
            if isinstance(msg["id"], float):
                fail(f"{self.label}: id voltou como float: {text}")
        return msg


def check_transcript(path: Path) -> None:
    checkers: dict[str, Checker] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        checker = checkers.setdefault(entry["transport"], Checker(f"transcript/{entry['transport']}"))
        if entry["dir"] == "in":
            checker.incoming(entry["text"])
        else:
            checker.outgoing(entry["text"])
    for name in ("panel", "window"):
        c = checkers.get(name)
        if c is None or c.count == 0:
            fail(f"transcript sem mensagens do transporte {name}")
        else:
            print(f"ok      transcript/{name}: {c.count} mensagens do runtime, {c.results} resultados conferidos")


# --- Ponta a ponta da janela ------------------------------------------------

def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Host:
    def __init__(self, godot: str):
        self.port = free_port()
        self.token = secrets.token_hex(32)
        self.proc = subprocess.Popen(
            [godot, "--headless", "--path", str(RUNTIME), "--script", "res://tests/preview/preview_host.gd",
             "--", "--vn-preview-port", str(self.port), "--vn-preview-token", self.token],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.url = f"ws://127.0.0.1:{self.port}"

    async def wait_listening(self, timeout: float = 30.0) -> None:
        """Espera a linha "ouvindo" do preview_host.gd (sem abrir conexão, que ocuparia a vaga)."""
        self.log: list[str] = []
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = await asyncio.wait_for(asyncio.to_thread(self.proc.stdout.readline), timeout)
            if not line:
                raise RuntimeError(f"o runtime saiu com {self.proc.wait()}: {''.join(self.log)}")
            self.log.append(line)
            if "preview_host: ouvindo" in line:
                return
        raise RuntimeError("o runtime não abriu a porta")

    def output(self) -> str:
        try:
            out, _ = self.proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            return ""
        return "".join(self.log) + (out or "")

    def kill(self) -> None:
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()


async def rpc(ws, checker: Checker, id_, method, params=None) -> dict:
    msg = {"jsonrpc": "2.0", "id": id_, "method": method}
    if params is not None:
        msg["params"] = params
    text = json.dumps(msg)
    checker.incoming(text)
    await ws.send(text)
    while True:
        reply = checker.outgoing(await asyncio.wait_for(ws.recv(), 5))
        if reply.get("id") == id_:
            return reply


async def expect_close(ws, code: int, label: str) -> None:
    import websockets
    try:
        await asyncio.wait_for(ws.recv(), 8)
        fail(f"{label}: recebeu mensagem em vez de fechar com {code}")
    except websockets.ConnectionClosed as e:
        got = e.rcvd.code if e.rcvd else None
        if got != code:
            fail(f"{label}: fechou com {got}, esperado {code}")
        else:
            print(f"ok      {label}: fechou com {code}")


async def end_to_end(godot: str) -> None:
    import websockets
    host = Host(godot)
    checker = Checker("janela/ponta-a-ponta")
    try:
        await host.wait_listening()
        if "127.0.0.1" not in host.url:
            fail("a janela deveria ouvir só em 127.0.0.1")

        # Token errado: 4401, sem resposta, e a vaga fica livre.
        async with websockets.connect(host.url) as ws:
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "session.hello",
                                      "params": {"token": "f" * 64, "protocol": "1.0"}}))
            await expect_close(ws, 4401, "token errado")
        # Mensagem antes do hello: 4401.
        async with websockets.connect(host.url) as ws:
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "preview.get_state"}))
            await expect_close(ws, 4401, "mensagem antes do hello")
        # 5 s sem hello: 4401.
        t0 = time.monotonic()
        async with websockets.connect(host.url) as ws:
            await expect_close(ws, 4401, "5 s sem hello")
        if not 4.5 <= time.monotonic() - t0 <= 8:
            fail(f"prazo do hello levou {time.monotonic() - t0:.1f} s")

        # Sessão de verdade.
        ws = await websockets.connect(host.url)
        r = await rpc(ws, checker, 1, "session.hello", {"token": host.token, "protocol": "1.0", "studio_version": "0.1.0"})
        if "result" not in r or r["result"]["features"] != ["show_screen"]:
            fail(f"hello: {r}")
        r = await rpc(ws, checker, 2, "preview.start", {})
        if r.get("error", {}).get("data", {}).get("state") != "READY":
            fail(f"start em READY: {r}")
        r = await rpc(ws, checker, 3, "preview.load", {"bundle_path": "/p/.vnstudio/preview/narrative", "assets_base": "/p/assets"})
        if "result" not in r:
            fail(f"load: {r}")
        r = await rpc(ws, checker, 4, "preview.get_state", {"include": ["variables"]})
        if "result" not in r:
            fail(f"get_state: {r}")
        r = await rpc(ws, checker, 5, "preview.reload", {"patch": []})
        if r.get("error", {}).get("code") != -32601:
            fail(f"reload sem handler: {r}")
        checker.incoming("[1]")
        await ws.send("[1]")
        batch = checker.outgoing(await asyncio.wait_for(ws.recv(), 5))
        if batch.get("error", {}).get("code") != -32600:
            fail(f"lote: {batch}")
        print(f"ok      sessão na janela ({checker.count} mensagens válidas pelo schema)")

        # Segunda conexão: 4409; a primeira continua aberta.
        async with websockets.connect(host.url) as ws2:
            await expect_close(ws2, 4409, "segunda conexão")
        r = await rpc(ws, checker, 6, "preview.get_state")
        if "result" not in r:
            fail("a primeira conexão caiu com a segunda")

        # Queda da conexão: o runtime sai sozinho em 10 s.
        await ws.close()
        t0 = time.monotonic()
        while host.proc.poll() is None and time.monotonic() - t0 < 20:
            await asyncio.sleep(0.1)
        elapsed = time.monotonic() - t0
        if host.proc.poll() is None:
            fail("o runtime não saiu 20 s depois da queda")
        elif not 9.0 <= elapsed <= 13.0:
            fail(f"o runtime saiu {elapsed:.1f} s depois da queda (esperado ~10 s)")
        else:
            print(f"ok      saiu {elapsed:.1f} s depois da queda, com código {host.proc.returncode}")
        out = host.output()
        if host.token in out:
            fail("o token apareceu no log do runtime")
        if any(tag in out for tag in ("SCRIPT ERROR", "ERROR:")):
            fail(f"erros no log do runtime:\n{out}")
    finally:
        host.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--transcript", type=Path)
    parser.add_argument("--godot")
    args = parser.parse_args()
    if not args.transcript and not args.godot:
        parser.error("dê --transcript, --godot ou os dois")
    global VALIDATORS
    VALIDATORS = load_validators()
    if args.transcript:
        check_transcript(args.transcript)
    if args.godot:
        asyncio.run(end_to_end(args.godot))
    print(f"{len(failures)} falha(s)." if failures else "Protocolo do Preview: tudo conforme o schema.")
    return 1 if failures else 0


VALIDATORS = None

if __name__ == "__main__":
    sys.exit(main())
