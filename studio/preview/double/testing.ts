/**
 * Cliente mínimo para os testes do dublê: manda requisições pela ponte em texto e junta respostas e
 * notificações. Não é o cliente do Studio (esse chega com o painel do Preview, M6-10).
 */
import type { FakePreviewRuntime } from './FakePreviewRuntime';
import type { JsonObject, RpcErrorObject } from './types';

export interface Received {
  id?: number | string | null;
  method?: string;
  params?: JsonObject;
  result?: unknown;
  error?: RpcErrorObject;
}

export class TestClient {
  readonly received: Received[] = [];
  private nextId = 1;

  constructor(readonly runtime: FakePreviewRuntime) {
    runtime.onmessage = (text) => this.received.push(JSON.parse(text) as Received);
  }

  /** Espera as entregas pendentes (o dublê entrega em microtarefas). */
  async flush(): Promise<void> {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  }

  async call(method: string, params?: JsonObject): Promise<Received> {
    const id = this.nextId++;
    this.runtime.send(JSON.stringify({ jsonrpc: '2.0', id, method, ...(params ? { params } : {}) }));
    await this.flush();
    const response = this.received.find((m) => m.id === id && !m.method);
    if (!response) throw new Error(`sem resposta para ${method}`);
    return response;
  }

  /** Chama e devolve `result`, falhando se veio erro. */
  async ok<T = JsonObject>(method: string, params?: JsonObject): Promise<T> {
    const response = await this.call(method, params);
    if (response.error) throw new Error(`${method}: ${response.error.message} ${JSON.stringify(response.error.data)}`);
    return response.result as T;
  }

  notifications(method?: string): JsonObject[] {
    return this.received.filter((m) => m.method && (!method || m.method === method)).map((m) => ({ method: m.method, ...m.params }));
  }

  /** Nomes das notificações recebidas desde `from` (índice em `received`). */
  trace(from = 0): string[] {
    return this.received.slice(from).filter((m) => m.method).map((m) => m.method as string);
  }
}
