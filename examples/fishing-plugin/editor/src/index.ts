// Fishing Minigame: parte de editor (Editor SDK ^1.0.0).
// Roda num iframe isolado; só fala com o Studio pela bridge (Plugin SDK §10).
import type { PluginContext } from "@vnstudio/editor-sdk";

export async function activate(ctx: PluginContext): Promise<void> {
  // Substituto do minijogo no Preview no Studio, que não executa GDScript (§10.6).
  ctx.preview.renderActivityMock("fishing_game", (el, params, done) => {
    const target = (params as { target_fish?: number }).target_fish ?? 3;
    el.innerHTML = `
      <p>Fishing session (goal: ${target} fish)</p>
      <label>Fish <input type="number" min="0" value="${target}" data-k="fish_count"></label>
      <label>Score <input type="number" min="0" value="${target * 100}" data-k="score"></label>
      <button data-outcome="won">Won</button> <button data-outcome="lost">Lost</button>`;
    const read = (k: string) => Number((el.querySelector(`[data-k=${k}]`) as HTMLInputElement).value);
    const onClick = (e: Event) => {
      const outcome = (e.target as HTMLElement).dataset.outcome;
      if (outcome) done(outcome, { won: outcome === "won", fish_count: read("fish_count"), score: read("score") });
    };
    el.addEventListener("click", onClick);
    return () => el.removeEventListener("click", onClick);
  });
}

export async function deactivate(): Promise<void> {}
