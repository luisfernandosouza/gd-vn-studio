import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

/** Variável de ambiente do token do GitHub na CI (spec 09 §3.1). */
export const GITHUB_TOKEN_ENV = 'VNSTUDIO_GITHUB_TOKEN';

/**
 * Onde o Studio e a CLI guardam o token de leitura no chaveiro do sistema. O mesmo nome nos três:
 * serviço `vnstudio` e conta `github` (Keychain e Secret Service), alvo `vnstudio:github` no
 * Credential Manager do Windows.
 */
export const KEYCHAIN_SERVICE = 'vnstudio';
export const KEYCHAIN_ACCOUNT = 'github';

export type TokenProvider = () => Promise<string | undefined>;

/** Lê o token do chaveiro do sistema. Sem chaveiro, sem a ferramenta ou sem entrada, `undefined`. */
export const systemKeychainToken: TokenProvider = async () => {
  try {
    if (process.platform === 'darwin') {
      const { stdout } = await run('security', [
        'find-generic-password',
        '-s',
        KEYCHAIN_SERVICE,
        '-a',
        KEYCHAIN_ACCOUNT,
        '-w',
      ]);
      return stdout.trim() || undefined;
    }
    if (process.platform === 'win32') {
      const { stdout } = await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', WINDOWS_CRED_READ], {
        windowsHide: true,
      });
      return stdout.trim() || undefined;
    }
    const { stdout } = await run('secret-tool', ['lookup', 'service', KEYCHAIN_SERVICE, 'account', KEYCHAIN_ACCOUNT]);
    return stdout.trim() || undefined;
  } catch {
    return undefined;
  }
};

/** CredRead do advapi32 pelo PowerShell: o Windows não tem comando pronto que leia a senha. */
const WINDOWS_CRED_READ = `
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class VnCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment;
    public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredReadW(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr cred);
  public static string Read(string target) {
    IntPtr p; if (!CredReadW(target, 1, 0, out p)) return "";
    try { var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2); } finally { CredFree(p); }
  }
}
'@
[VnCred]::Read('${KEYCHAIN_SERVICE}:${KEYCHAIN_ACCOUNT}')
`;

/**
 * Token do GitHub para `github:` (spec 09 §3.1): `VNSTUDIO_GITHUB_TOKEN` quando definida (CI), senão o
 * chaveiro do sistema. O token nunca é gravado no projeto.
 */
export function githubTokenProvider(
  env: NodeJS.ProcessEnv = process.env,
  keychain: TokenProvider = systemKeychainToken,
): TokenProvider {
  return async () => env[GITHUB_TOKEN_ENV]?.trim() || (await keychain());
}

/** Mensagem de quando falta o token (spec 09 §3.1: "explica como criar um token só de leitura"). */
export function tokenHelp(repo: string): string {
  return (
    `Não foi possível ler ${repo} no GitHub. Se o repositório é privado, crie um token só de leitura ` +
    `(GitHub → Settings → Developer settings → Fine-grained tokens, com acesso a ${repo} e permissão ` +
    `"Contents: Read-only") e guarde-o no Studio (Preferências → GitHub) ou, na CI, na variável ${GITHUB_TOKEN_ENV}.`
  );
}
