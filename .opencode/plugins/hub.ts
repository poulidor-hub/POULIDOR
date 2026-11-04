// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

/**
 * Plugin Hub - outillage opencode pour le Hub et les apps generees depuis
 * HUBapp_TEMPLATE_base. Accompagne le MCP `hub` (hub_mcp/server.py).
 *
 * Source de verite : POULIDOR/.opencode/plugins/hub.ts
 * Copie template synchronisee via `make sync-hub-tooling` (verif : `make sync-hub-tooling-check`).
 *
 * Format : plugin OpenCode V2 — export default { id, setup(ctx) }
 * (plugin API V2 : https://opencode.ai/v2/docs/build/plugins).
 * Pur JS sans dependance : aucun import runtime requis.
 *
 * Garde-fou : pour les operations destructrices (suppression Hub, restore,
 * revocation, prod, rm -rf, down -v, push --force...), on ne fait JAMAIS
 * confiance a un "allow" automatique : on retrograde la decision en "ask".
 * On ne deny jamais et on n'allow jamais de soi-meme.
 */
const DESTRUCTIVE = [
  /\bhub_\w*_delete\b/i,
  /\bhub_backup_restore\b/i,
  /\bhub_app_(delete|approve|toggle_active)\b/i,
  /\brm\s+-[a-z]*r[a-z]*f/i,
  /docker\s+compose\s+down\s+.*(-v|--volumes)/i,
  /\bDELETE_DATA\b/i,
  /\bdrop\s+database\b/i,
  /git\s+push\s+.*--force/i,
  /\bclean-all\b/i,
  /\b(prod|production)\b.*\b(deploy|up|down|restart)\b/i,
]

export default {
  id: "poulidor-hub",
  async setup(ctx) {
    await ctx.permission.hook("evaluate", async (event) => {
      try {
        // Un "deny" configure n'atteint jamais ce hook ; on ne retrograde
        // que les "allow" automatiques. Les "ask" restent "ask".
        if (event.effect !== "allow") return
        let metadata = ""
        try {
          metadata = JSON.stringify(event.metadata ?? {})
        } catch {
          metadata = ""
        }
        const haystack = [event.action, ...event.resources, metadata]
          .filter(Boolean)
          .join(" ")
        if (DESTRUCTIVE.some((re) => re.test(haystack))) {
          event.effect = "ask"
          event.message =
            "Garde-fou POULIDOR : operation potentiellement destructrice, confirmation humaine requise."
        }
      } catch {
        // En cas d'erreur du garde-fou, ne jamais bloquer l'action : on
        // laisse la decision configuree telle quelle.
        return
      }
    })
  },
}
