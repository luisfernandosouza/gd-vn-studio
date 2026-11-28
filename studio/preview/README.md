# Painel do Preview

Ponte entre o Studio e o runtime exportado para Web, que roda neste painel do webview ([Preview Protocol §1.1](../../docs/specs/07-preview-protocol.md)). A ponte usa `vnPreview.send` / `vnPreview.onmessage`, com o mesmo JSON-RPC da janela nativa.

O painel (M6-10) fala com o runtime pelo protocolo JSON-RPC da spec 07. O Preview real chega na M6-14; até lá, o painel fala com o dublê em [`double/`](double/) quando o export Web do runtime não está embutido no Studio.

## Dublê do runtime (`double/`, M0-09)

Um runtime falso em TypeScript que fala o JSON-RPC da spec 07, para os testes e para desenvolver o Preview, o painel "por que não apareceu" e o Menu Editor sem o runtime Web.

```ts
import { FakePreviewRuntime, demoStory, installFakeBridge } from '../preview/double';

// Como o painel: instala window.vnPreview com send/onmessage.
const { bridge, runtime } = installFakeBridge(window);
bridge.onmessage = (text) => console.log(JSON.parse(text));
bridge.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'session.hello', params: { protocol: '1.0' } }));

// Como a janela: token obrigatório, fechamento 4401 em onclose.
const win = new FakePreviewRuntime({ story: demoStory(), transport: 'window', token, platform: 'windows' });
```

| Arquivo | Conteúdo |
|---|---|
| `FakePreviewRuntime.ts` | O dublê: estados (§2), `hello` e autenticação (§1.1, §1.2), todos os métodos do §3, erros do §6, notificações com `seq`/`phase` na ordem do §4.2, `GameState` (§5), `storage.write` no painel com `user_data: "project"` (§1.4), recarga incremental e completa |
| `logic.ts` | Variáveis com as validações de escrita do RT §6.2, condições, expressões e efeitos: o mínimo para andar pelas cenas |
| `story.ts` | `demoStory()`: o projeto de exemplo das specs, com as cenas lidas de `docs/specs/examples/demo-project` e as avaliações do Scheduler gravadas; `DEMO` tem os ids |
| `bridge.ts` | `installFakeBridge(window)`: a ponte `vnPreview` do painel ligada ao dublê |
| `schema.ts` | Validação com o Ajv contra `docs/specs/schemas/preview-protocol.schema.json` (só testes e Node) |
| `recordings/` | Notificações gravadas (`log`, `plugin.*`, `error`, `storage.delete`, `session.closing`), repetidas com `runtime.replay()` |
| `testing.ts` | Cliente mínimo para os testes |

**Validação na CI.** Os testes (`npm test`, workflow `studio.yml`) criam o dublê com `validator: loadProtocolSchema()`: cada mensagem que ele monta é validada antes de sair, contra a forma geral do schema e, nas respostas, contra `$defs/<Método>_result`; uma mensagem inválida lança. Depois de cada teste, tudo o que saiu é validado de novo e os `seq` são conferidos. O Ajv compila com `new Function`, que a CSP do Studio não permite, então no app o dublê roda sem validação.

**O que o dublê não faz.** Não roda o Scheduler: em cada ponto de seleção usa a próxima avaliação gravada do capítulo (`DoubleChapter.selections`) e, quando elas acabam, sai do capítulo. Não valida `params` e `payload` de atividades contra os schemas do plugin, não sorteia (`random_int` devolve o mínimo), não agrupa notificações (`batch`, opcional no §4.1) e não desenha nada. Em `preview.step`, uma fala esperando o jogador conta como avançada; escolha, interação e atividade esperam `preview.input`. Num `interact`, `advance` usa a saída (`exit`), que não tem id. Em `LOADED`, `preview.get_state` responde `preview: "PAUSED"`, porque o schema só aceita `RUNNING` ou `PAUSED`.

## Painel do Preview (M6-10)

| Arquivo | Conteúdo |
|---|---|
| `urls.ts` | Origem do `vnpreview` por sistema (`vnpreview://localhost` no macOS e no Linux, `http://vnpreview.localhost` no Windows) e as URLs dos três prefixos (`/runtime/`, `/project/assets/`, `/project/preview/narrative/`) |
| `client.ts` | Cliente JSON-RPC 2.0 sobre a ponte `vnPreview` (`send` / `onmessage`), com os 16 métodos do §3 tipados pelo schema, `PreviewRpcError` com o `data.code` do §6 e conferência de `seq`. Mensagem malformada da página é ignorada e registrada |
| `transport.ts` | `IframeTransport` (página do runtime num iframe, `postMessage` `to-runtime` / `from-runtime`, só aceita a janela do iframe) e `doubleTransport` (dublê do M0-09) |
| `session.ts` | `PreviewSession`: `hello`, bundle em `.vnstudio/preview/narrative/`, `load`, recarga incremental a cada edição, todos os métodos, modo stream, log e `storage.*` |
| `project-input.ts` | Lê o projeto pelo `ProjectFs` para a entrada do compilador do bundle (mesmo resultado que `loadProject` da CLI). O modelo do M6-02 o substitui |
| `bundle-files.ts`, `user-files.ts` | Grava o bundle canônico (JCS) e aplica `storage.write` / `storage.delete` só dentro de `.vnstudio/preview/user/` |
| `PreviewPanel.tsx`, `store.ts` | Barra (iniciar, parar, pausar, passo, **Modo stream**, recarregar do disco) e a sessão ativa para os editores chamarem `update` |

**Recarga a cada edição.** `session.update(input)` recompila entidade por entidade (`planReload`, M5-02) e manda em `preview.reload` só as trocas que mudaram (`patch`). Vão por recarga completa (`bundle_url` + `changed`): mudança em `/project`, `/variables`, `/aliases`, nos idiomas ou em `plugins.json`; patch recusado com `BUNDLE_INVALID`; e uma a cada 50 incrementais, para conferir memória e disco (PP §3). Edições que chegam juntas se enfileiram e só a última vale.

**Protocolo `vnpreview` (lado nativo).** `src-tauri/src/vnpreview.rs` serve só o projeto aberto, pelo mapa fixo de três prefixos; qualquer outro caminho dá 404, e segmentos com `..`, separadores, `:` ou NUL, ou links que saem da pasta, são recusados. `.wasm` sai com `application/wasm`. O Studio troca o mapa ao abrir e fechar o projeto (`preview_open_project`, `preview_close_project`).
