/** Dublê do runtime do Preview (M0-09). Ver `README.md` desta pasta. */
export { FakePreviewRuntime, RpcCode, CloseCode, PROTOCOL_VERSION } from './FakePreviewRuntime';
export type { FakePreviewRuntimeOptions } from './FakePreviewRuntime';
export { installFakeBridge } from './bridge';
export type { VnPreviewBridge } from './bridge';
export { demoStory, DEMO } from './story';
export type * from './types';
