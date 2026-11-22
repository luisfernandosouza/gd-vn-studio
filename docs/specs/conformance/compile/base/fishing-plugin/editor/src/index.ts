// Fishing Minigame: parte de editor (Editor SDK ^1.0.0).
// Roda num iframe isolado; só fala com o Studio pela bridge (Plugin SDK §10).
import type { PluginContext } from "@vnstudio/editor-sdk";

export async function activate(ctx: PluginContext): Promise<void> {
  // O Preview roda o minijogo real (§10.6). Este comando só abre o Preview
  // direto no nó de pescaria selecionado, para testar o minijogo sem jogar a cena toda.
  let selected: { scene: string; node: string; type?: string } | undefined;
  ctx.events.on("node.selected", (payload) => {
    selected = payload as typeof selected;
  });
  ctx.commands.register("play_fishing_here", async () => {
    if (!selected || selected.type !== "activity") {
      ctx.notifications.show("Select a fishing activity step first.", "info");
      return;
    }
    await ctx.preview.start({ scene: selected.scene, node: selected.node });
  });
}

export async function deactivate(): Promise<void> {}
