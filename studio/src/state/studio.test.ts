import { describe, expect, it } from 'vitest';
import { useStudioStore } from './studio';

describe('useStudioStore', () => {
  it('começa sem estar pronto e muda com markReady', () => {
    useStudioStore.setState({ ready: false });
    useStudioStore.getState().markReady();
    expect(useStudioStore.getState().ready).toBe(true);
  });
});
