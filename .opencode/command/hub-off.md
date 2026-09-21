---
description: Désactive le MCP hub dans opencode.json pour alléger le contexte (~66 outils) — redémarrage d'opencode requis.
agent: build
---

Désactive le serveur MCP `hub` dans `opencode.json` (racine du dépôt), sans toucher au reste du fichier :

1. Bascule `"enabled"` du bloc `mcp.hub` à `false` via python3 (préserve le format JSON) :

```bash
python3 - <<'EOF'
import json
p = "opencode.json"
cfg = json.load(open(p))
cfg["mcp"]["hub"]["enabled"] = False
json.dump(cfg, open(p, "w"), indent=2, ensure_ascii=False)
print("mcp.hub.enabled =", cfg["mcp"]["hub"]["enabled"])
EOF
```

2. Vérifie le résultat : `grep -A3 '"hub"' opencode.json`.
3. Rappelle à l'utilisateur : **quitter et relancer opencode** pour que la désactivation
   prenne effet. En attendant le redémarrage, les outils `hub_*` restent disponibles dans
   la session courante.
4. Pour réactiver : commande `/hub-on`.
