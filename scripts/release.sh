#!/bin/bash
# Cuts a release: ./scripts/release.sh 1.2.3
# Moves the CHANGELOG "Unreleased" notes under the new version, bumps VERSION,
# commits, tags and pushes. The Release workflow then builds and publishes it.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: scripts/release.sh <version>  (e.g. 1.0.1)}"
OLD="$(cat VERSION)"
TODAY="$(date +%Y-%m-%d)"
REPO="https://github.com/emcee5000/satori"

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main." >&2; exit 1; }
git rev-parse "v$NEW" >/dev/null 2>&1 && { echo "Tag v$NEW already exists." >&2; exit 1; }

# There must be something to release.
notes="$(awk '/^## \[Unreleased\]/{on=1;next} on && /^## \[/{exit} on' CHANGELOG.md | grep -v '^[[:space:]]*$' || true)"
[[ -n "$notes" ]] || { echo "CHANGELOG has no Unreleased entries." >&2; exit 1; }

echo "$NEW" > VERSION

# "## [Unreleased]" -> a fresh empty Unreleased section followed by the new version.
python3 - "$NEW" "$OLD" "$TODAY" "$REPO" <<'PY'
import sys, re
new, old, today, repo = sys.argv[1:]
p = "CHANGELOG.md"
s = open(p).read()
s = s.replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{new}] - {today}\n", 1)
s = re.sub(r"^\[Unreleased\]: .*$", f"[Unreleased]: {repo}/compare/v{new}...HEAD\n[{new}]: {repo}/compare/v{old}...v{new}", s, count=1, flags=re.M)
open(p, "w").write(s)
PY

git add VERSION CHANGELOG.md
git commit -q -m "Release $NEW"
git tag -a "v$NEW" -m "Satori $NEW"
git push -q origin main "v$NEW"
echo "✓ Pushed v$NEW. The Release workflow will build and publish it:"
echo "  $REPO/actions/workflows/release.yml"
