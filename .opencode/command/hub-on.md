---
description: Active le MCP hub (~66 outils) dans opencode.json pour la prochaine session (redémarrage d'opencode requis).
agent: build
---

Active le serveur MCP `hub` dans `opencode.json` (racine du dépôt), sans toucher au reste du fichier :

1. Bascule `"enabled"` du bloc `mcp.hub` à `true` via python3 (préserve le format JSON) :

```bash
python3 - <<'EOF'
import json
p = "opencode.json"
cfg = json.load(open(p))
cfg["mcp"]["hub"]["enabled"] = True
json.dump(cfg, open(p, "w"), indent=2, ensure_ascii=False)
print("mcp.hub.enabled =", cfg["mcp"]["hub"]["enabled"])
EOF
```

2. Vérifie le résultat : `grep -A3 '"hub"' opencode.json`.
3. Rappelle à l'utilisateur : **quitter et relancer opencode** pour charger le MCP (la
   config n'est pas hot-reloadable). D'ici là, les opérations Hub passent par `hubctl`
   ou les scripts bash.
4. Si l'utilisateur veut revenir en arrière : commande `/hub-off`.
