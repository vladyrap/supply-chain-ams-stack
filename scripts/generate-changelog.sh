#!/bin/bash
# =============================================================================
# generate-changelog.sh — Genera CHANGELOG.md desde tags git
# =============================================================================
# v1.2.7-prod · Saca git log entre tags consecutivos y formatea como markdown.
# Uso:
#   ./generate-changelog.sh            # genera CHANGELOG.md en cwd
#   ./generate-changelog.sh /path/file # output al archivo dado
# =============================================================================
set -euo pipefail

OUT="${1:-CHANGELOG.md}"

{
  echo "# Changelog"
  echo ""
  echo "Auto-generated from git tags. Last refresh: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
} > "$OUT"

TAGS=$(git tag --sort=-v:refname | grep -E '^v[0-9]' || true)

if [ -z "$TAGS" ]; then
  echo "No tags yet. Bail." >> "$OUT"
  exit 0
fi

PREV=""
echo "$TAGS" | while read -r TAG; do
  if [ -z "$PREV" ]; then
    PREV="$TAG"
    continue
  fi
  echo "## $PREV" >> "$OUT"
  DATE=$(git log -1 --format=%aI "$PREV" 2>/dev/null | cut -dT -f1)
  echo "_$DATE_" >> "$OUT"
  echo "" >> "$OUT"
  git log "$TAG..$PREV" --pretty=format:"- %s (%an)" --no-merges 2>/dev/null >> "$OUT" || true
  echo "" >> "$OUT"
  echo "" >> "$OUT"
  PREV="$TAG"
done

# Última (oldest) tag sin previo
LAST=$(echo "$TAGS" | tail -1)
echo "## $LAST" >> "$OUT"
DATE=$(git log -1 --format=%aI "$LAST" 2>/dev/null | cut -dT -f1)
echo "_$DATE_" >> "$OUT"
echo "" >> "$OUT"
git log "$LAST" --pretty=format:"- %s (%an)" --no-merges -20 2>/dev/null >> "$OUT" || true

echo "Generated $OUT"
