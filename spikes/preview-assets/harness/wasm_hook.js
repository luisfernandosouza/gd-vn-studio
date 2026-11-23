// Entra no <head> do export (html/head_include): guarda a memória do WASM do motor em
// window.__vnWasmMemory, para a bancada medir o tamanho do heap (ele cresce e nunca encolhe).
(() => {
  const keep = (r) => {
    const inst = r && (r.instance || r);
    const mem = inst && inst.exports && Object.values(inst.exports).find(e => e instanceof WebAssembly.Memory);
    if (mem) window.__vnWasmMemory = mem;
    return r;
  };
  const stream = WebAssembly.instantiateStreaming;
  if (stream) WebAssembly.instantiateStreaming = (...a) => stream.apply(WebAssembly, a).then(keep);
  const inst = WebAssembly.instantiate;
  WebAssembly.instantiate = (...a) => inst.apply(WebAssembly, a).then(keep);
  WebAssembly.Memory = new Proxy(WebAssembly.Memory, {
    construct(t, args) { const m = new t(...args); window.__vnWasmMemory = m; return m; },
  });
})();
