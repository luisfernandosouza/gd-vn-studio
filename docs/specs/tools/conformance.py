#!/usr/bin/env python3
"""Implementação de referência dos vetores de conformidade (spec 08).

Cobre as partes do comportamento que os dois interpretadores (Runtime Godot e
Preview do Studio) DEVEM reproduzir bit a bit: expressões e funções (Data Model
§6.1.1), condições (§5), efeitos como transação (§6.2), conversão e formatação
de números (Runtime Spec §12.1), PCG32 e derivação de sementes (§12.2) e a
decisão do Scene Scheduler num ponto de seleção (§4).

Uso:
    python3 tools/conformance.py              # confere todos os casos de conformance/
    python3 tools/conformance.py caso.json    # confere só os arquivos dados
"""
import base64, hashlib, hmac, json, math, sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASES = HERE.parent / "conformance"
INT_MAX = 2 ** 53 - 1
M64 = 2 ** 64 - 1


class VNError(Exception):
    def __init__(self, code, msg=""):
        super().__init__(f"{code}: {msg}"); self.code = code


# ---------------------------------------------------------------- valores
# Um valor é (tipo, valor): tipo ∈ boolean, integer, number, string, enum.

def lit(v):
    if isinstance(v, bool): return ("boolean", v)
    if isinstance(v, int): return ("integer", v)
    if isinstance(v, float): return ("number", v)
    if isinstance(v, str): return ("string", v)
    raise VNError("TYPE_MISMATCH", f"literal {v!r}")

def check_int(i):
    if not -INT_MAX <= i <= INT_MAX: raise VNError("OUT_OF_RANGE", f"inteiro {i} fora de ±(2^53 − 1)")
    return ("integer", i)

def check_num(x):
    if not math.isfinite(x): raise VNError("OUT_OF_RANGE", f"número não finito {x}")
    return ("number", x)

def to_int_trunc(x):
    """number → integer, truncando em direção a zero (Data Model §6.2)."""
    if not math.isfinite(x) or not -INT_MAX <= math.trunc(x) <= INT_MAX: raise VNError("OUT_OF_RANGE", f"{x} não cabe em integer")
    return int(math.trunc(x))

def is_num(t): return t in ("integer", "number")
def fval(v): return float(v[1])


def js_number_to_string(x):
    """Number.prototype.toString do ECMAScript (menor representação que volta ao mesmo valor)."""
    if x == 0: return "0"
    if x < 0: return "-" + js_number_to_string(-x)
    r = repr(x)                                  # Python também gera os dígitos mais curtos
    mant, _, exp = r.partition("e")
    exp = int(exp) if exp else 0
    if "." in mant:
        ip, fp = mant.split(".")
    else:
        ip, fp = mant, ""
    digits = (ip + fp).lstrip("0")
    lead_zeros = len(ip + fp) - len((ip + fp).lstrip("0"))
    n = len(ip) + exp - lead_zeros                # posição do ponto decimal em relação aos dígitos
    digits = digits.rstrip("0") or "0"
    k = len(digits)
    if k <= n <= 21: return digits + "0" * (n - k)
    if 0 < n <= 21: return digits[:n] + "." + digits[n:]
    if -6 < n <= 0: return "0." + "0" * (-n) + digits
    e = n - 1
    sign = "+" if e >= 0 else "-"
    return (digits[0] + ("." + digits[1:] if k > 1 else "")) + "e" + sign + str(abs(e))


def jcs(v):
    """JSON canônico (RFC 8785, JCS), usado no content_hash, em assinaturas de saves e perfil e no build.json (Build System §5.1)."""
    if v is None: return "null"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, int): return str(v)
    if isinstance(v, float):
        if v != v or v in (float("inf"), float("-inf")): raise ValueError("número não finito")
        return js_number_to_string(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list): return "[" + ",".join(jcs(x) for x in v) + "]"
    if isinstance(v, dict):
        keys = sorted(v, key=lambda k: k.encode("utf-16-be"))          # ordem por unidades UTF-16
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + jcs(v[k]) for k in keys) + "}"
    raise TypeError(type(v))


def save_integrity(doc, key):
    """Assinatura de save ou perfil: HMAC-SHA256 do JCS do documento sem o campo integrity (Build System §8.3)."""
    doc = {k: v for k, v in doc.items() if k != "integrity"}
    return "hmac-sha256-" + base64.b64encode(hmac.new(key, jcs(doc).encode("utf-8"), hashlib.sha256).digest()).decode()


def to_text(v):
    """Conversão usada por concat (Runtime Spec §12.1)."""
    t, x = v
    if t == "boolean": return "true" if x else "false"
    if t == "integer": return str(x)
    if t == "number":
        if x == int(x) and abs(x) <= INT_MAX: return str(int(x))
        return js_number_to_string(x)
    return x


# Tabela de formatação por idioma (Runtime Spec §12.1): (decimal, milhar, dígitos mínimos para agrupar)
NUMBER_FORMATS = {
    "en": (".", ",", 4), "ja": (".", ",", 4), "zh-Hans": (".", ",", 4), "zh-Hant": (".", ",", 4),
    "pt-BR": (",", ".", 4), "it": (",", ".", 4), "de": (",", ".", 4),
    "es": (",", ".", 5), "fr": (",", " ", 4),
}

OVERRIDES = {}   # project.json → settings.number_formats (Runtime Spec §12.1)

def number_format(locale):
    if locale in OVERRIDES:
        o = OVERRIDES[locale]; return (o["decimal"], o.get("group", ""), o.get("min_grouping", 4))
    if locale in NUMBER_FORMATS: return NUMBER_FORMATS[locale]
    lang = locale.split("-")[0]
    return NUMBER_FORMATS.get(lang, NUMBER_FORMATS["en"])

def format_number(v, locale):
    """Formatação de número na interpolação: até 2 casas, meio-para-longe-do-zero sobre a
    representação decimal mais curta (a mesma de concat), sem zeros à direita."""
    t, x = v
    dec_sep, grp_sep, min_grp = number_format(locale)
    if t == "integer":
        d = Decimal(x)
    else:
        d = Decimal(to_text(v)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    neg = d < 0
    s = format(abs(d), "f")
    ip, _, fp = s.partition(".")
    fp = fp.rstrip("0")
    if len(ip) >= min_grp and grp_sep:
        groups = []
        while len(ip) > 3: groups.insert(0, ip[-3:]); ip = ip[:-3]
        groups.insert(0, ip); ip = grp_sep.join(groups)
    out = ip + (dec_sep + fp if fp else "")
    return ("-" if neg and out.strip("0" + dec_sep + grp_sep) else "") + out

def format_record(score, fmt, locale):
    """Exibição de uma marca de recorde (Plugin SDK §9.1): integer e number como na interpolação;
    time_ms como m:ss.cc (h:mm:ss.cc a partir de uma hora), centésimos truncados, separador decimal do idioma."""
    if fmt == "time_ms":
        cs = int(score) // 10
        h, rest = divmod(cs, 360000); m, rest = divmod(rest, 6000); sec, c = divmod(rest, 100)
        dec = number_format(locale)[0]
        return (f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}") + f"{dec}{c:02d}"
    if fmt == "integer": return format_number(("integer", int(score)), locale)
    return format_number(("number", float(score)), locale)

def submit_record(board, entries, new):
    """Plugin SDK §9.1: insere a marca, mantém as `keep` melhores; empate fica com a mais antiga.
    Devolve (posição 1…keep ou 0, lista nova)."""
    desc = board["order"] == "desc"
    better = (lambda a, b: a > b) if desc else (lambda a, b: a < b)
    pos = len(entries)
    for i, e in enumerate(entries):
        if better(new["score"], e["score"]): pos = i; break
    out = entries[:pos] + [new] + entries[pos:]
    out = out[:board["keep"]]
    return (pos + 1 if pos < board["keep"] else 0), out

def interpolate_value(v, locale):
    t, x = v
    if t == "boolean": return "true" if x else "false"
    if is_num(t): return format_number(v, locale)
    return x


# ---------------------------------------------------------------- expressões

FNS_ARITY = {"add": (2, 2), "sub": (2, 2), "mul": (2, 2), "div": (2, 2), "mod": (2, 2), "min": (2, 8), "max": (2, 8),
             "clamp": (3, 3), "round": (1, 1), "floor": (1, 1), "ceil": (1, 1), "abs": (1, 1), "concat": (1, 8),
             "random_int": (2, 2)}

class Env:
    def __init__(self, variables, rng=None, history=None, events=None):
        self.vars = variables                     # qid → {"type", "value", "default"?, "constraints"?}
        self.rng = rng
        self.history = history or {}
        self.events = events or []

    def read(self, qid):
        parts = qid.split(".")
        h = self.history
        if qid == "sys.selection_count": return ("integer", h.get("selection_count", 0))
        if len(parts) == 4 and parts[0] == "sys" and parts[1] == "scenes":
            sc = h.get("scenes", {}).get(parts[2], {})
            if parts[3] == "plays": return ("integer", sc.get("plays", 0))
            if parts[3] == "last_selection": return ("integer", sc.get("last_selection", -1))
        d = self.vars.get(qid)
        if d is None: raise VNError("VARIABLE_NOT_FOUND", qid)
        return (d["type"], d["value"])


def arith(fn, a, b):
    if not (is_num(a[0]) and is_num(b[0])): raise VNError("TYPE_MISMATCH", f"{fn} exige números")
    both_int = a[0] == b[0] == "integer"
    if fn == "div":
        if b[1] == 0: raise VNError("OUT_OF_RANGE", "divisão por zero")
        return check_num(fval(a) / fval(b))
    if fn == "mod":
        if not both_int: raise VNError("TYPE_MISMATCH", "mod exige inteiros")
        if b[1] == 0: raise VNError("OUT_OF_RANGE", "mod por zero")
        return check_int(a[1] % b[1])           # Python: sinal do divisor
    op = {"add": lambda x, y: x + y, "sub": lambda x, y: x - y, "mul": lambda x, y: x * y}[fn]
    if both_int: return check_int(op(a[1], b[1]))
    return check_num(op(fval(a), fval(b)))

def round_half_away(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)

def evaluate(e, env):
    if not isinstance(e, dict): return lit(e)
    if "var" in e: return env.read(e["var"])
    if "if" in e: return evaluate(e["then"] if check_conditions(e["if"], env) else e["else"], env)
    if "fn" in e:
        fn, args = e["fn"], e.get("args", [])
        lo, hi = FNS_ARITY[fn]
        if not lo <= len(args) <= hi: raise VNError("TYPE_MISMATCH", f"{fn}: aridade")
        if fn == "random_int":
            a, b = (evaluate(x, env) for x in args)
            if a[0] != "integer" or b[0] != "integer": raise VNError("TYPE_MISMATCH", "random_int exige inteiros")
            return ("integer", env.rng.random_int(a[1], b[1]))
        vs = [evaluate(x, env) for x in args]
        if fn == "concat": return ("string", "".join(to_text(v) for v in vs))
        if fn in ("add", "sub", "mul", "div", "mod"): return arith(fn, vs[0], vs[1])
        if not all(is_num(v[0]) for v in vs): raise VNError("TYPE_MISMATCH", f"{fn} exige números")
        all_int = all(v[0] == "integer" for v in vs)
        if fn in ("min", "max"):
            best = vs[0]
            for v in vs[1:]:
                if (fval(v) < fval(best)) if fn == "min" else (fval(v) > fval(best)): best = v
            return ("integer", best[1]) if all_int else ("number", fval(best))
        if fn == "clamp":
            v, lo_, hi_ = vs
            r = lo_ if fval(lo_) > fval(hi_) else (lo_ if fval(v) < fval(lo_) else hi_ if fval(v) > fval(hi_) else v)
            return ("integer", r[1]) if all_int else ("number", fval(r))
        v = vs[0]
        if fn == "abs": return check_int(abs(v[1])) if v[0] == "integer" else check_num(abs(v[1]))
        if v[0] == "integer": return v
        r = {"round": round_half_away, "floor": math.floor, "ceil": math.ceil}[fn](v[1]) if math.isfinite(v[1]) else math.inf
        if not math.isfinite(r): raise VNError("OUT_OF_RANGE", "não finito")
        return check_int(int(r))
    raise VNError("TYPE_MISMATCH", f"expressão desconhecida {e}")


# ---------------------------------------------------------------- condições

def compare(op, a, b):
    if op in ("equals", "not_equals"):
        if is_num(a[0]) and is_num(b[0]): eq = fval(a) == fval(b)
        elif a[0] in ("string", "enum") and b[0] in ("string", "enum"): eq = a[1] == b[1]
        elif a[0] == b[0]: eq = a[1] == b[1]
        else: raise VNError("TYPE_MISMATCH", f"{a[0]} {op} {b[0]}")
        return eq if op == "equals" else not eq
    if op in ("greater_than", "greater_than_or_equal", "less_than", "less_than_or_equal"):
        if not (is_num(a[0]) and is_num(b[0])): raise VNError("TYPE_MISMATCH", op)
        x, y = fval(a), fval(b)
        return {"greater_than": x > y, "greater_than_or_equal": x >= y, "less_than": x < y, "less_than_or_equal": x <= y}[op]
    if op == "contains":
        if a[0] != "string" or b[0] != "string": raise VNError("TYPE_MISMATCH", op)
        return b[1] in a[1]
    raise VNError("TYPE_MISMATCH", op)

def check_condition(c, env):
    if isinstance(c, list): return all(check_condition(x, env) for x in c)
    if "all" in c: return all(check_condition(x, env) for x in c["all"])
    if "any" in c: return any(check_condition(x, env) for x in c["any"])
    if "not" in c: return not check_condition(c["not"], env)
    if "event_since_last_selection" in c: return c["event_since_last_selection"] in env.events
    a = env.read(c["variable"]); op = c["operator"]
    if op == "is_default":
        return compare("equals", a, lit(env.vars[c["variable"]]["default"]))
    if op in ("in", "not_in"):
        inside = any(compare("equals", a, lit(x)) for x in c["value"])
        return inside if op == "in" else not inside
    b = evaluate(c["value"], env) if isinstance(c["value"], dict) else lit(c["value"])
    return compare(op, a, b)

def check_conditions(conds, env): return check_condition(conds, env)


# ---------------------------------------------------------------- efeitos

def apply_effects(effects, env):
    """Transação: devolve as mudanças ou levanta VNError sem alterar env."""
    work = {k: dict(v) for k, v in env.vars.items()}
    tenv = Env(work, env.rng, env.history, env.events)
    changes = []
    for eff in effects:
        qid, op = eff["variable"], eff["op"]
        if qid not in work: raise VNError("VARIABLE_NOT_FOUND", qid)
        d = work[qid]; t = d["type"]; old = d["value"]
        if op == "toggle":
            if t != "boolean": raise VNError("TYPE_MISMATCH", "toggle")
            new = not old
        elif op == "reset":
            new = d["default"]
        else:
            v = evaluate(eff["value"], tenv)
            if op == "set":
                if t == "integer" and v[0] == "number": new = to_int_trunc(v[1])
                elif t == "number" and v[0] == "integer": new = float(v[1])
                elif (t in ("string", "enum") and v[0] == "string") or t == v[0]: new = v[1]
                else: raise VNError("TYPE_MISMATCH", f"set {qid} ({t}) = {v[0]}")
            else:
                if not is_num(t) or not is_num(v[0]): raise VNError("TYPE_MISMATCH", f"{op} {qid}")
                fn = {"add": "add", "subtract": "sub", "multiply": "mul"}[op]
                r = arith(fn, (t, old), v)
                new = to_int_trunc(r[1]) if t == "integer" and r[0] == "number" else (float(r[1]) if t == "number" else r[1])
        if t == "integer": check_int(new)
        cons = d.get("constraints", {}); mode = cons.get("on_overflow", "clamp")
        if is_num(t):
            lo, hi = cons.get("min"), cons.get("max")
            if (lo is not None and new < lo) or (hi is not None and new > hi):
                if mode == "reject": raise VNError("CONSTRAINT_VIOLATION", f"{qid} = {new}")
                new = max(lo, new) if lo is not None and new < lo else min(hi, new)
                if t == "number": new = float(new)
        if t == "string" and cons.get("max_length") is not None and len(new) > cons["max_length"]:
            if mode == "reject": raise VNError("CONSTRAINT_VIOLATION", f"{qid} longa demais")
            new = new[:cons["max_length"]]
        if t == "enum" and new not in cons.get("values", []): raise VNError("CONSTRAINT_VIOLATION", f"{new} fora do enum")
        if new != old or type(new) != type(old):
            changes.append({"variable": qid, "old": old, "new": new})
        d["value"] = new
    return work, changes


# ---------------------------------------------------------------- PCG32 (Runtime Spec §12.2)

MULT, INC = 6364136223846793005, 1442695040888963407

class PCG32:
    def __init__(self, seed=None, state=None):
        if state is not None: self.state = state
        else:
            self.state = 0; self._step(); self.state = (self.state + seed) & M64; self._step()

    def _step(self): self.state = (self.state * MULT + INC) & M64

    def next_u32(self):
        old = self.state; self._step()
        xs = (((old >> 18) ^ old) >> 27) & 0xFFFFFFFF
        rot = old >> 59
        return ((xs >> rot) | (xs << ((-rot) & 31))) & 0xFFFFFFFF

    def next_u64(self):
        hi = self.next_u32(); lo = self.next_u32()
        return (hi << 32) | lo

    def random_int(self, lo, hi):
        """Inteiro uniforme em [lo, hi], inclusivo, por rejeição (sem viés)."""
        if lo > hi: lo, hi = hi, lo
        span = hi - lo + 1
        if span <= 2 ** 32:
            threshold = (2 ** 32 - span) % span
            while True:
                r = self.next_u32()
                if r >= threshold: return lo + r % span
        threshold = (2 ** 64 - span) % span
        while True:
            r = self.next_u64()
            if r >= threshold: return lo + r % span

    def unit(self):
        """Real em [0, 1): next_u32 / 2^32."""
        return self.next_u32() / 4294967296.0

def seed_from_hash(*parts):
    return int.from_bytes(hashlib.sha256(b"".join(parts)).digest()[:8], "big")

def activity_seed(game_seed, selection_count, node_uuid, activity_index):
    return seed_from_hash(game_seed.to_bytes(8, "big"), selection_count.to_bytes(8, "big"),
                          bytes.fromhex(node_uuid.replace("-", "")), activity_index.to_bytes(4, "big"))

def plugin_seed(game_seed, namespace):
    return seed_from_hash(game_seed.to_bytes(8, "big"), namespace.encode("utf-8"))

def weighted_pick(scenes, rng):
    """Runtime Spec §4.3: ordena pelo id, r = unit() × soma, primeira com acumulado > r."""
    ordered = sorted(scenes, key=lambda s: s["id"])
    total = 0.0
    for s in ordered: total += float(s.get("scheduling", {}).get("weight", 1))
    r = rng.unit() * total
    acc = 0.0
    for s in ordered:
        acc += float(s.get("scheduling", {}).get("weight", 1))
        if acc > r: return s
    return ordered[-1]


# ---------------------------------------------------------------- Scene Scheduler (Runtime Spec §4)

def select(case):
    """Decisão de um ponto de seleção. Devolve o traço de scheduler.evaluated + histórico depois."""
    chapter = case["chapter"]; scenes = {s["id"]: s for s in case["scenes"]}
    st = case.get("state", {})
    history = json.loads(json.dumps(st.get("history", {})))
    history.setdefault("selection_count", 0); history.setdefault("scenes", {}); history.setdefault("groups", {})
    history.setdefault("fallback_streak", 0)
    rng = PCG32(state=int(st["rng_state"], 16)) if st.get("rng_state") else None
    env = Env(st.get("variables", {}), rng, history, history.get("events_since_selection", []))
    groups = {g["id"]: g for g in chapter.get("exclusive_groups", []) + case.get("project_groups", [])}
    n = history["selection_count"]

    def sch(s): return s.get("scheduling", {})
    def hist(sid): return history["scenes"].get(sid, {})

    def blocked(s):
        p = sch(s)
        if p.get("mode", "scheduled") != "scheduled": return "mode_manual"
        mp = p.get("max_plays", 1)
        if mp is not None and hist(s["id"]).get("plays", 0) >= mp: return "max_plays"
        cd = p.get("cooldown", 0); last = hist(s["id"]).get("last_selection")
        if cd and last is not None and not n - last > cd: return "cooldown"
        for g in p.get("exclusive_groups", []):
            members = history["groups"].get(g, [])
            if s["id"] not in members and len(members) >= groups.get(g, {}).get("max_plays", 1): return "exclusive_group"
        if not check_conditions(p.get("conditions", []), env): return "conditions"
        return None

    def accept(sid):
        s = scenes.get(sid)
        if s and s.get("chapter") in (chapter["id"], None) and (sch(s).get("mode") == "manual" or blocked(s) is None): return True
        return False

    out = {"selection_count": n, "chapter": chapter["id"], "candidates": []}
    def start(sid, reason):
        h = history["scenes"].setdefault(sid, {})
        h["last_selection"] = history["selection_count"]; h["starts"] = h.get("starts", 0) + 1
        history["selection_count"] += 1
        history["fallback_streak"] = history["fallback_streak"] + 1 if reason == "fallback" else 0
        out.update(action="start_scene", chosen=sid, reason=reason); return out
    def finish(action, reason):
        out.update(action=action, chosen=None, reason=reason); return out

    plugin_request = history.pop("pending_request", None)
    content_request = case.get("content_request")
    if content_request is not None:
        if accept(content_request): return start(content_request, "request"), history
        out["request_refused"] = {"scene": content_request, "by": "content"}
    comp = chapter.get("completion", {})
    if "conditions" in comp and check_conditions(comp["conditions"], env): return finish("exit_chapter", "completion"), history
    if plugin_request is not None:
        if accept(plugin_request): return start(plugin_request, "plugin_request"), history
        out["request_refused"] = {"scene": plugin_request, "by": "plugin"}

    include_global = chapter.get("include_global_scenes", True)
    cands = sorted((s for s in scenes.values() if s.get("chapter") == chapter["id"] or (s.get("chapter") is None and include_global)),
                   key=lambda s: s["id"])
    E = []
    for s in cands:
        b = blocked(s)
        out["candidates"].append({"scene": s["id"], "eligible": b is None, **({"blocked_by": b} if b else {})})
        if b is None: E.append(s)
    if not E:
        mode = comp.get("on_exhausted", "advance")
        if mode == "scene":
            if history["fallback_streak"] >= 100: return finish("exit_chapter", "exhausted"), history
            return start(comp["fallback_scene"], "fallback"), history
        return finish("end_game" if mode == "end_game" else "exit_chapter", "exhausted"), history
    top = max(sch(s).get("priority", 100) for s in E)
    T = [s for s in E if sch(s).get("priority", 100) == top]
    for c in out["candidates"]:
        if c["eligible"] and sch(scenes[c["scene"]]).get("priority", 100) < top: c["blocked_by"] = "lower_priority"
    if len(T) == 1: chosen, reason = T[0], "priority"
    else:
        reason = "tie_break"
        if chapter.get("scheduler", {}).get("tie_breaker", "deterministic") == "weighted_random":
            chosen = weighted_pick(T, rng)
        else:
            chosen = min(T, key=lambda s: (hist(s["id"]).get("plays", 0), hist(s["id"]).get("last_selection", -1),
                                           (0, sch(s)["order"]) if "order" in sch(s) else (1, 0), s["id"]))
        for c in out["candidates"]:
            if c["scene"] in {s["id"] for s in T} and c["scene"] != chosen["id"]: c["blocked_by"] = "tie_break"
    for c in out["candidates"]:
        if c["scene"] != chosen["id"] and c["eligible"] and "blocked_by" not in c: c["blocked_by"] = "lower_priority"
    if rng: out["rng_state"] = f"{rng.state:016x}"
    return start(chosen["id"], reason), history


# ---------------------------------------------------------------- execução dos casos

def typed_vars(vs):
    out = {}
    for k, d in (vs or {}).items():
        d = dict(d)
        if d["type"] == "number" and isinstance(d["value"], int) and not isinstance(d["value"], bool): d["value"] = float(d["value"])
        out[k] = d
    return out

def run_case(c):
    k = c["kind"]
    if k in ("expression", "effects", "condition"):
        rng = PCG32(state=int(c["rng_state"], 16)) if c.get("rng_state") else None
        env = Env(typed_vars(c.get("variables")), rng, events=c.get("events"))
        try:
            if k == "expression":
                t, v = evaluate(c["expr"], env); return {"type": t, "value": v}
            if k == "condition": return {"value": check_conditions(c["conditions"], env)}
            _, changes = apply_effects(c["effects"], env); return {"changes": changes}
        except VNError as e:
            return {"error": e.code}
    if k == "record":
        OVERRIDES.clear()
        rank, entries = submit_record(c["board"], c["entries"], c["submit"])
        res = {"rank": rank, "entries": entries}
        if "locale" in c: res["display"] = [format_record(e["score"], c["board"]["format"], c["locale"]) for e in entries]
        return res
    if k == "canonical":
        text = jcs(json.loads(c["json"]))
        return {"text": text, "hash": "sha256-" + base64.b64encode(hashlib.sha256(text.encode("utf-8")).digest()).decode()}
    if k == "hmac":
        return {"integrity": save_integrity(json.loads(c["json"]), bytes.fromhex(c["key"]))}
    if k == "flow":
        OVERRIDES.clear(); return {"trace": run_flow(c)}
    if k == "text":
        OVERRIDES.clear(); OVERRIDES.update(c.get("number_formats", {}))
        if c["mode"] == "record": return {"text": format_record(c["value"] if not isinstance(c["value"], dict) else c["value"]["value"], c["format"], c["locale"])}
        v = lit(c["value"]) if not (isinstance(c["value"], dict)) else (c["value"]["type"], c["value"]["value"])
        if v[0] == "number": v = ("number", float(v[1]))
        if c["mode"] == "concat": return {"text": to_text(v)}
        return {"text": interpolate_value(v, c["locale"])}
    if k == "rng":
        op = c["op"]
        if op == "sequence":
            r = PCG32(seed=int(c["seed"], 16)); return {"values": [r.next_u32() for _ in range(c["count"])], "state_after": f"{r.state:016x}"}
        if op == "random_int":
            r = PCG32(seed=int(c["seed"], 16)); return {"values": [r.random_int(c["min"], c["max"]) for _ in range(c["count"])]}
        if op == "activity_seed":
            return {"seed": f"{activity_seed(int(c['seed'], 16), c['selection_count'], c['node'], c['activity_index']):016x}"}
        if op == "plugin_seed":
            return {"seed": f"{plugin_seed(int(c['seed'], 16), c['namespace']):016x}"}
    if k == "selection":
        try:
            out, history = select(c)
        except VNError as e:
            return {"error": e.code}
        res = {"action": out["action"], "chosen": out["chosen"], "reason": out["reason"],
               "candidates": out["candidates"], "selection_count_after": history["selection_count"],
               "fallback_streak_after": history["fallback_streak"]}
        if "request_refused" in out: res["request_refused"] = out["request_refused"]
        if "rng_state" in out: res["rng_state_after"] = out["rng_state"]
        return res
    raise ValueError(f"kind desconhecido {k}")


# ---------------------------------------------------------------- fluxo de cena (spec 08, kind flow)

INTERP_RE = __import__("re").compile(r"\{\{|\}\}|\{([^{}]*)\}")

def interpolate(text, env, locale):
    def sub(m):
        if m.group(0) == "{{": return "{"
        if m.group(0) == "}}": return "}"
        return interpolate_value(env.read(m.group(1).strip()), locale)
    return INTERP_RE.sub(sub, text)

TYPE_DEFAULT = {"boolean": False, "integer": 0, "number": 0.0, "string": "", "enum": None}

def resolve_result(effects, payload, env):
    """on_result.effects: {result} vira literal; campo ausente ou de tipo errado → default do {result} ou do tipo (Runtime Spec §5.3 passo 6)."""
    out = []
    for e in effects:
        e = dict(e); v = e.get("value")
        if isinstance(v, dict) and "result" in v:
            t = env.vars[e["variable"]]["type"]
            cur = payload
            for part in v["result"].split("."): cur = cur.get(part) if isinstance(cur, dict) else None
            ok = cur is not None and {"boolean": isinstance(cur, bool), "integer": isinstance(cur, (int, float)) and not isinstance(cur, bool) and float(cur).is_integer(),
                                      "number": isinstance(cur, (int, float)) and not isinstance(cur, bool), "string": isinstance(cur, str), "enum": isinstance(cur, str)}[t]
            val = (int(cur) if t == "integer" else cur) if ok else v.get("default", TYPE_DEFAULT[t] if t != "enum" else env.vars[e["variable"]]["default"])
            e["value"] = {"type": "number", "value": float(val)} if t == "number" and not isinstance(val, bool) else val
            if isinstance(e["value"], dict): e["value"] = float(val)
        out.append(e)
    return out

def run_flow(c):
    """Executa uma cena nó a nó com as entradas do jogador e devolve o traço (Runtime Spec §5)."""
    scene = c["scene"]; locale = c.get("locale", "en")
    env = Env(typed_vars(c.get("variables")), None, events=[])
    for d in scene.get("variables", []):
        env.vars[f"scene.{d['key']}"] = {"type": d["type"], "value": float(d["default"]) if d["type"] == "number" else d["default"], "default": d["default"], **({"constraints": d["constraints"]} if "constraints" in d else {})}
    nodes = scene["nodes"]; index = {n["id"]: i for i, n in enumerate(nodes)}
    inputs = list(c.get("inputs", [])); trace = []; queue = []
    def emit(name, payload=None): queue.append(name)
    def drain():
        while queue: trace.append({"event": queue.pop(0)})
    def transaction(effects):
        try:
            work, changes = apply_effects(effects, env)
        except VNError as e:
            return e.code
        env.vars = work
        if changes: trace.append({"changes": changes})
        return None
    def nxt(i, n): return index[n["next"]] if n.get("next") else i + 1
    cf = c.get("content_filter", False)                    # modo stream (Data Model §10.4)
    i = index[scene.get("start") or nodes[0]["id"]]; guard = 0
    trace.append({"event": "sys.scene_started"})
    while True:
        guard += 1
        if guard > 10000: return trace + [{"error": "INFINITE_LOOP"}]
        if i >= len(nodes):
            trace.append({"event": "sys.scene_ended"}); trace.append({"end": "schedule"}); break
        n = nodes[i]; t = n["type"]
        if n.get("censor") == ("skip" if cf else "only"):  # o passo não vale neste modo: segue sem executar
            i = nxt(i, n); continue
        trace.append({"node": n["id"]})
        if t == "line":
            trace.append({"text": interpolate(n["censored_text"] if cf and "censored_text" in n else n["text"], env, locale)})
            inp = inputs.pop(0) if inputs else None
            if inp != "advance": return trace + [{"waiting": "line"}]
            i = nxt(i, n)
        elif t == "choice":
            vis = [o for o in n["options"] if check_conditions(o.get("visible_if", []), env)]
            if not vis: i = nxt(i, n); continue
            trace.append({"options": [{"id": o["id"], "enabled": check_conditions(o.get("enabled_if", []), env)} for o in vis]})
            inp = inputs.pop(0) if inputs else None
            if not (isinstance(inp, dict) and "choose" in inp): return trace + [{"waiting": "choice"}]
            o = next(o for o in vis if o["id"] == inp["choose"])
            eff = list(o.get("effects", []))
            if n.get("record"): eff.append({"op": "set", "variable": n["record"], "value": o.get("value", o["id"])})
            transaction(eff)
            emit("sys.choice_made"); drain()
            i = index[o["goto"]] if o.get("goto") else nxt(i, n)
        elif t == "effects":
            code = transaction(n["effects"])
            if code == "CONSTRAINT_VIOLATION" and n.get("on_fail"): i = index[n["on_fail"]]; continue
            if code and code != "CONSTRAINT_VIOLATION": trace.append({"error": code})
            i = nxt(i, n)
        elif t == "branch":
            goto = next((cs["goto"] for cs in n["cases"] if check_conditions(cs["conditions"], env)), n.get("else"))
            i = index[goto] if goto else nxt(i, n)
        elif t == "jump":
            i = index[n["goto"]]
        elif t == "emit":
            emit(n["event"]); drain(); i = nxt(i, n)
        elif t == "plugin":
            inp = inputs.pop(0) if inputs else None
            if not (isinstance(inp, dict) and "activity" in inp): return trace + [{"waiting": "plugin"}]
            a = inp["activity"]
            if a.get("failed"):
                trace.append({"event": "sys.activity_failed"}); goto = n.get("on_error")
                i = index[goto] if goto else nxt(i, n); continue
            if not a.get("skipped"):
                transaction(resolve_result(n.get("on_result", {}).get("effects", []), a.get("payload", {}), env))
            emit("sys.activity_completed"); drain()
            goto = n.get("on_result", {}).get("outcomes", {}).get(a["outcome"])
            i = index[goto] if goto else nxt(i, n)
        elif t == "end":
            then = n.get("then", "schedule")
            trace.append({"event": "sys.scene_ended"}); trace.append({"end": then}); break
        else:   # background, show, hide, audio, wait, interact sem entrada: palco não entra no traço
            i = nxt(i, n)
    return trace


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool) and float(a) == float(b)
    if isinstance(a, dict) and isinstance(b, dict): return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list): return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b and type(a) == type(b)


def main(paths):
    files = [Path(p) for p in paths] or sorted(CASES.glob("*.json"))
    total = fails = 0
    for f in files:
        doc = json.loads(f.read_text(encoding="utf-8"))
        for c in doc["cases"]:
            total += 1
            got = run_case(c)
            if not same(got, c["expect"]):
                fails += 1
                print(f"FALHOU {f.name}#{c['id']}\n  esperado: {json.dumps(c['expect'], ensure_ascii=False)}\n  obtido:   {json.dumps(got, ensure_ascii=False)}")
    print(f"\n{total - fails}/{total} vetores conferem com a referência.")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
