import type { Plugin } from "@opencode-ai/plugin"

/**
 * Plugin Hub - outillage opencode pour le Hub et les apps generees depuis
 * HUBapp_TEMPLATE_base. Accompagne le MCP `hub` (hub_mcp/server.py).
 *
 * Source de verite : POULIDOR/.opencode/plugins/hub.ts
 * Copie template synchronisee via `make sync-hub-tooling` (verif : `make sync-hub-tooling-check`).
 *
 * Garde-fou : pour les operations destructrices (suppression Hub, restore,
 * revocation, prod, rm -rf, down -v, push --force...), on ne fait JAMAIS
 * confiance a un "allow" automatique : on retrograde la decision en "ask".
 * On ne deny jamais et on n'allow jamais de soi-meme.
 */
const DESTRUCTIVE = [
  /\bhub_\w*_delete\b/i,
  /\bhub_backup_restore\b/i,
  /\bhub_pki_revoke\b/i,
  /\bhub_user_reset_password\b/i,
  /\bhub_app_(delete|approve|toggle_active)\b/i,
  /\brm\s+-[a-z]*r[a-z]*f/i,
  /docker\s+compose\s+down\s+.*(-v|--volumes)/i,
  /\bDELETE_DATA\b/i,
  /\bdrop\s+database\b/i,
  /git\s+push\s+.*--force/i,
  /\bclean-all\b/i,
  /\b(prod|production)\b.*\b(deploy|up|down|restart)\b/i,
]

export const HubPlugin: Plugin = async () => {
  return {
    "permission.asked": async (input, output) => {
      try {
        if (output.status !== "allow") return
        const pattern = Array.isArray(input.pattern)
          ? input.pattern.join(" ")
          : input.pattern ?? ""
        const haystack = [input.type, input.title, pattern]
          .filter(Boolean)
          .join(" ")
        if (DESTRUCTIVE.some((re) => re.test(haystack))) {
          output.status = "ask"
        }
      } catch {
        return
      }
    },
  }
}

export default HubPlugin
