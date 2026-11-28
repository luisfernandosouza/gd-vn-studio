/**
 * URLs do painel do Preview (PP §1.1). A origem do protocolo próprio do Tauri depende do sistema:
 * `vnpreview://localhost/` no macOS e no Linux e `http://vnpreview.localhost/` no Windows (WebView2).
 * O Studio monta toda URL a partir da origem e de um dos três prefixos do mapa fixo, e nunca põe um
 * caminho absoluto do disco nela.
 */

export type PreviewPlatform = 'windows' | 'macos' | 'linux';

export const PREVIEW_PREFIXES = {
  runtime: '/runtime/',
  assets: '/project/assets/',
  bundle: '/project/preview/narrative/',
} as const;

/** Sistema do webview, pelo `navigator` (o Tauri não tem um mapa próprio para isso no lado da página). */
export function detectPlatform(nav: { userAgent?: string; platform?: string } = typeof navigator === 'undefined' ? {} : navigator): PreviewPlatform {
  const text = `${nav.userAgent ?? ''} ${nav.platform ?? ''}`;
  if (/Windows|Win32|Win64/i.test(text)) return 'windows';
  if (/Mac|iPhone|iPad/i.test(text)) return 'macos';
  return 'linux';
}

export function previewOrigin(platform: PreviewPlatform): string {
  return platform === 'windows' ? 'http://vnpreview.localhost' : 'vnpreview://localhost';
}

export interface PreviewUrls {
  origin: string;
  /** A página do runtime (export Web para o Preview), aberta no iframe. */
  runtimePage: string;
  /** `assets_base` de `preview.load`: a pasta `assets/` do projeto. */
  assetsBase: string;
  /** `bundle_url` de `preview.load` e `preview.reload`. */
  bundleUrl: string;
}

export function previewUrls(platform: PreviewPlatform): PreviewUrls {
  const origin = previewOrigin(platform);
  return {
    origin,
    runtimePage: `${origin}${PREVIEW_PREFIXES.runtime}index.html`,
    assetsBase: `${origin}${PREVIEW_PREFIXES.assets}`,
    bundleUrl: `${origin}${PREVIEW_PREFIXES.bundle}`,
  };
}

/** Pasta do Preview dentro do projeto (spec 09 §3.4), fora do Git. */
export const PREVIEW_DIR = '.vnstudio/preview';
export const PREVIEW_BUNDLE_DIR = `${PREVIEW_DIR}/narrative`;
export const PREVIEW_USER_DIR = `${PREVIEW_DIR}/user`;
