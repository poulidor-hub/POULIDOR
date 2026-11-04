#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)
"""apply_license_headers.py — pose les en-têtes SPDX du parc POULIDOR.

Ajoute proprement, en tête des fichiers sources suivis par git :
  * ``SPDX-License-Identifier: AGPL-3.0-or-later`` — fichiers du Cœur du HUB ;
  * ``SPDX-License-Identifier: MIT`` — fichiers du gabarit (``HUBapp_TEMPLATE_base``)
    et du design system (``HUBCSS``),
suivis de la ligne de copyright ``Copyright (C) 2026 POULIDOR Audit &
Développement (Valérian Poulidor)``.

Garanties :
  * insertion au niveau octets : le reste du fichier est préservé à l'octet
    près (fins de ligne LF/CRLF mélangées, caractères form-feed, etc.) ;
  * n'écrase jamais un en-tête SPDX existant ;
  * ne touche pas aux fichiers portant déjà un ``Copyright`` dans leurs 5
    premières lignes (code tiers/vendored — à traiter manuellement) ;
  * préserve les shebangs (``#!/usr/bin/env ...``) et les déclarations
    d'encodage PEP 263 (l'en-tête est inséré APRÈS eux, jamais avant) ;
  * préserve l'encodage UTF-8 et le BOM éventuel ; les fichiers non
    décodables en UTF-8 sont ignorés ;
  * n'opère que sur les fichiers suivis par git (``git ls-files``) → les
    ``node_modules``, builds et artefacts ne sont jamais touchés ;
  * par défaut en mode dry-run : rien n'est écrit sans ``--apply``.

Usage (méta-repo, mapping mixte AGPL/MIT) :
    python3 scripts/apply_license_headers.py                # dry-run
    python3 scripts/apply_license_headers.py --apply

Usage depuis un dépôt sous-module (licence unique) :
    python3 <méta>/scripts/apply_license_headers.py --root . --license agpl --apply
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

COPYRIGHT_LINE = "Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)"

LICENSES = {
    "agpl": ["SPDX-License-Identifier: AGPL-3.0-or-later", COPYRIGHT_LINE],
    "mit": ["SPDX-License-Identifier: MIT", COPYRIGHT_LINE],
}

# Style de commentaire par extension (prioritaire sur STYLE_BY_NAME).
STYLE_BY_EXT = {
    ".py": "hash", ".sh": "hash", ".bash": "hash",
    ".yml": "hash", ".yaml": "hash", ".toml": "hash",
    ".sql": "dash",
    ".js": "line", ".mjs": "line", ".cjs": "line",
    ".ts": "line", ".tsx": "line", ".jsx": "line",
    ".scss": "line", ".sass": "line",
    ".css": "block",
    ".html": "html", ".htm": "html", ".vue": "html",
}

# Style de commentaire pour fichiers sans extension (nom exact, minuscule).
STYLE_BY_NAME = {
    "dockerfile": "hash",
    "makefile": "hash",
}

# Dossiers jamais en-têtés (défense en profondeur ; git ls-files exclut déjà
# l'ignoré). Fichiers manifestement générés ou minifiés. Les workflows GitHub
# sont exclus : leur modification exige le scope OAuth `workflow` (poussée
# impossible avec un simple token `repo`) et ils restent couverts par le
# LICENSE du dépôt.
SKIP_DIR_PARTS = {"node_modules", "dist", "build", "vendor", "vendored",
                  ".venv", "venv", "__pycache__", "coverage", ".next",
                  ".github/workflows"}
SKIP_SUFFIXES = (".min.js", ".min.css", ".min.mjs", ".d.ts")
MAX_BYTES = 1_000_000  # au-delà : probablement généré/minifié, on s'abstient

CODING_RE = re.compile(r"^\s*#.*?coding[:=]\s*[-\w.]+")
BOM = b"\xef\xbb\xbf"


def comment(style: str, line: str) -> str:
    if style == "hash":
        return f"# {line}"
    if style == "line":
        return f"// {line}"
    if style == "dash":
        return f"-- {line}"
    if style == "block":
        return f"/* {line} */"
    if style == "html":
        return f"<!-- {line} -->"
    raise ValueError(f"style inconnu : {style}")


def header_block_bytes(style: str, license_id: str, eol: bytes) -> bytes:
    lines = [comment(style, l).encode("utf-8") for l in LICENSES[license_id]]
    # en-tête + ligne vide de séparation
    return b"".join(l + eol for l in lines) + eol


def insert_index(lines: list[str]) -> int:
    """Nombre de lignes à laisser devant l'en-tête (shebang + coding PEP 263)."""
    idx = 0
    if lines and lines[0].startswith("#!"):
        idx = 1
        if len(lines) > 1 and CODING_RE.match(lines[1]):
            idx = 2
    elif lines and CODING_RE.match(lines[0]):
        idx = 1
    return idx


def byte_offset_after_lines(raw: bytes, n_lines: int) -> int:
    """Décalage en octets juste après la n_lines-ième ligne de ``raw``."""
    pos = 0
    for _ in range(n_lines):
        nl = raw.find(b"\n", pos)
        if nl == -1:
            return len(raw)
        pos = nl + 1
    return pos


def detect_eol(raw: bytes) -> bytes:
    head = raw[:8192]
    if b"\r\n" in head:
        return b"\r\n"
    return b"\n"


def tracked_files(root: Path) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True,
    )
    return [p for p in out.stdout.decode("utf-8", "surrogateescape").split("\0") if p]


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Ajoute les en-têtes SPDX POULIDOR aux fichiers sources (dry-run par défaut).")
    ap.add_argument("--root", default=".", help="racine du dépôt à traiter (défaut : .)")
    ap.add_argument("--license", choices=sorted(LICENSES), default="agpl",
                    help="licence par défaut du dépôt (défaut : agpl)")
    ap.add_argument("--mit-dirs", nargs="*", default=[],
                    help="sous-dossiers (chemins relatifs) à traiter en MIT même "
                         "quand --license agpl (ex. HUBapp_TEMPLATE_base HUBCSS)")
    ap.add_argument("--apply", action="store_true",
                    help="écrit réellement les modifications (sinon simple dry-run)")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    probe = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True)
    if probe.returncode != 0:
        print(f"❌ {root} n'est pas un dépôt git", file=sys.stderr)
        return 2

    mit_dirs = [(root / d).resolve() for d in args.mit_dirs]

    pending: list[tuple[Path, str, str, bytes]] = []  # (path, rel, license_id, block)
    already: list[str] = []
    third_party: list[str] = []
    ignored: list[str] = []

    for rel in tracked_files(root):
        path = root / rel
        rpath = path.resolve()
        rel_parts = rel.split("/")
        if any(part in SKIP_DIR_PARTS for part in rel_parts):
            continue
        if any(rel_parts[i] == ".github" and rel_parts[i + 1] == "workflows"
               for i in range(len(rel_parts) - 1)):
            continue
        name = path.name.lower()
        if name.endswith(SKIP_SUFFIXES):
            continue
        style = STYLE_BY_EXT.get(path.suffix.lower()) or STYLE_BY_NAME.get(name)
        if style is None:
            continue
        try:
            if path.stat().st_size > MAX_BYTES:
                ignored.append(f"{rel} (>1 Mo)")
                continue
            raw = path.read_bytes()
        except OSError as e:
            ignored.append(f"{rel} ({e})")
            continue
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            ignored.append(f"{rel} (non UTF-8)")
            continue
        if "SPDX-License-Identifier" in text:
            already.append(rel)
            continue
        lines = text.splitlines()
        if any("Copyright" in l for l in lines[:5]):
            third_party.append(rel)
            continue
        if not lines or not any(l.strip() for l in lines):
            ignored.append(f"{rel} (vide)")
            continue

        license_id = "mit" if any(
            rpath == d or d in rpath.parents for d in mit_dirs) else args.license
        eol = detect_eol(raw)
        idx = insert_index(lines)
        off = byte_offset_after_lines(raw, idx)
        # BOM éventuel : l'offset d'insertion saute toujours les lignes de
        # code (shebang/coding) donc le BOM, s'il existe, est déjà devant.
        block = header_block_bytes(style, license_id, eol)
        pending.append((path, rel, license_id, raw[:off] + block + raw[off:]))
        print(f"  + {rel}  [{license_id}]")

    print(f"\n≡ racine {root} · défaut {args.license} · MIT sur {args.mit_dirs or '—'} · "
          f"mode {'APPLY' if args.apply else 'DRY-RUN'}")
    print(f"Σ à en-têter : {len(pending)} · déjà SPDX : {len(already)} · "
          f"tiers (Copyright présent, ignorés) : {len(third_party)} · ignorés : {len(ignored)}")
    for label, lst in (("déjà SPDX", already), ("tiers", third_party), ("ignorés", ignored)):
        for item in lst[:15]:
            print(f"  · {label} : {item}")
        if len(lst) > 15:
            print(f"  · {label} : … (+{len(lst) - 15} autres)")

    if pending and args.apply:
        for path, _rel, _lic, new_raw in pending:
            path.write_bytes(new_raw)
        print(f"✍  {len(pending)} fichiers écrits.")
    elif pending:
        print("\n(dry-run : relancez avec --apply pour écrire)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
