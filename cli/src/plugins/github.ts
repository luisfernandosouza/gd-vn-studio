import { valid } from 'semver';
import { NetworkError } from './errors.js';
import { decodeJson, type HttpGet, type HttpResponse } from './http.js';

const API = 'https://api.github.com';

export interface GithubRelease {
  owner: string;
  repo: string;
  tag: string;
  /** Versão tirada da tag: `v1.2.0` ou, no monorepo, `plugin-<namespace>-v1.2.0` (spec 09 §1). */
  version: string;
  asset: { name: string; apiUrl: string; downloadUrl: string };
}

/** Falta token, ou o token não dá acesso ao repositório (privado ou inexistente). */
export class GithubAccessError extends Error {
  constructor(
    readonly repo: string,
    readonly status: number,
  ) {
    super(`GitHub respondeu ${status} para ${repo}`);
    this.name = 'GithubAccessError';
  }
}

interface ApiRelease {
  tag_name: string;
  draft: boolean;
  assets: { name: string; url: string; browser_download_url: string }[];
}

function headers(token?: string, accept = 'application/vnd.github+json'): Record<string, string> {
  return {
    Accept: accept,
    'X-GitHub-Api-Version': '2022-11-28',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

function check(res: HttpResponse, repo: string): void {
  if (res.status === 401 || res.status === 403 || res.status === 404) throw new GithubAccessError(repo, res.status);
  if (res.status !== 200) throw new NetworkError(`GitHub respondeu ${res.status} para ${repo}`);
}

export function versionFromTag(tag: string): string | undefined {
  const m = /^(?:.*-)?v(\d+\.\d+\.\d+(?:[-+].*)?)$/.exec(tag);
  return m?.[1] && valid(m[1]) ? m[1] : undefined;
}

/** Escolhe o `.vnplugin` da Release: `<id>-<versão>.vnplugin`, ou o único `.vnplugin` dela. */
function pickAsset(rel: ApiRelease, id: string, version: string): ApiRelease['assets'][number] | undefined {
  const pkgs = rel.assets.filter((a) => a.name.endsWith('.vnplugin'));
  return pkgs.find((a) => a.name === `${id}-${version}.vnplugin`) ?? (pkgs.length === 1 ? pkgs[0] : undefined);
}

/** Releases publicadas (sem rascunhos) com um `.vnplugin` e tag com versão SemVer. */
export async function listReleases(
  http: HttpGet,
  owner: string,
  repo: string,
  id: string,
  token?: string,
): Promise<GithubRelease[]> {
  const out: GithubRelease[] = [];
  for (let page = 1; page <= 10; page++) {
    const res = await http(`${API}/repos/${owner}/${repo}/releases?per_page=100&page=${page}`, headers(token));
    check(res, `${owner}/${repo}`);
    const list = decodeJson<ApiRelease[]>(res.body);
    for (const rel of list) {
      const version = versionFromTag(rel.tag_name);
      if (rel.draft || !version) continue;
      const asset = pickAsset(rel, id, version);
      if (!asset) continue;
      out.push({
        owner,
        repo,
        tag: rel.tag_name,
        version,
        asset: { name: asset.name, apiUrl: asset.url, downloadUrl: asset.browser_download_url },
      });
    }
    if (list.length < 100) break;
  }
  return out;
}

const RELEASE_URL = /^https:\/\/github\.com\/([^/]+)\/([^/]+)\/releases\/download\/([^/]+)\/([^/]+)$/;

/**
 * Baixa o pacote de uma URL de Release (o `resolved` do lock). Com token, vai pela API (necessário em
 * repositório privado); sem token, baixa a URL direto, que é o caso dos plugins oficiais (SDK §13.2).
 */
export async function downloadReleaseAsset(http: HttpGet, url: string, token?: string): Promise<Uint8Array> {
  const m = RELEASE_URL.exec(url);
  if (token && m) {
    const [, owner, repo, tag, name] = m as unknown as [string, string, string, string, string];
    const repoName = `${owner}/${repo}`;
    const res = await http(`${API}/repos/${owner}/${repo}/releases/tags/${tag}`, headers(token));
    check(res, repoName);
    const asset = decodeJson<ApiRelease>(res.body).assets.find((a) => a.name === decodeURIComponent(name));
    if (!asset) throw new GithubAccessError(repoName, 404);
    const bin = await http(asset.url, headers(token, 'application/octet-stream'));
    check(bin, repoName);
    return bin.body;
  }
  const res = await http(url);
  if (m && (res.status === 401 || res.status === 403 || res.status === 404)) {
    throw new GithubAccessError(`${m[1]}/${m[2]}`, res.status);
  }
  if (res.status !== 200) throw new NetworkError(`${url} respondeu ${res.status}`);
  return res.body;
}
