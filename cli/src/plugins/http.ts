import { NetworkError } from './errors.js';

export interface HttpResponse {
  status: number;
  body: Uint8Array;
}

/** GET HTTP(S). Lança `NetworkError` quando não há resposta (sem internet); status de erro volta normalmente. */
export type HttpGet = (url: string, headers?: Record<string, string>) => Promise<HttpResponse>;

/**
 * Implementação com o `fetch` do Node. Redirecionamentos são seguidos; o `fetch` tira o `Authorization`
 * quando o redirecionamento muda de origem (o download de uma Release vai para outro host).
 */
export const fetchGet: HttpGet = async (url, headers = {}) => {
  let res: Response;
  try {
    res = await fetch(url, { headers: { 'User-Agent': 'vnstudio-cli', ...headers }, redirect: 'follow' });
  } catch (err) {
    throw new NetworkError(`sem resposta de ${url}`, { cause: err });
  }
  return { status: res.status, body: new Uint8Array(await res.arrayBuffer()) };
};

export function decodeJson<T>(body: Uint8Array): T {
  return JSON.parse(new TextDecoder().decode(body)) as T;
}
