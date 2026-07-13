#!/usr/bin/env bash
# manifest.sh — regenerate or verify docs/MANIFEST.sha256 (whole-kit integrity).
#
#   ops/manifest.sh            # recompute all hashes, rewrite the manifest
#   ops/manifest.sh --verify   # compare disk vs manifest; nonzero on any drift
#
# Scope: every kit file (tracked or new-and-unignored) EXCEPT the manifest
# itself (so it can hash stably), ops/sessions/** (mutable session state),
# and config/cluster.env (secret; gitignored anyway). Root-relative paths.
set -euo pipefail
cd "$(dirname "$0")/.."
MANIFEST=docs/MANIFEST.sha256

list_files() {
  git ls-files -co --exclude-standard \
    | grep -Ev '^(docs/MANIFEST\.sha256|ops/sessions/|config/cluster\.env$)' \
    | LC_ALL=C sort
}

compute() {
  local f
  # -b: binary mode ("*" marker) so hashes are byte-exact on Windows too
  while IFS= read -r f; do sha256sum -b "$f"; done < <(list_files)
}

regen() {
  {
    echo "# spark-landing-kit integrity manifest — whole kit, repo-root-relative paths."
    echo "# Verify from the repo root: sha256sum -c docs/MANIFEST.sha256"
    echo "# Regenerate after any content change: ops/manifest.sh (--verify to check)."
    echo "# Excluded: this file, ops/sessions/** (mutable), config/cluster.env (secret)."
    compute
  } > "$MANIFEST"
  echo "wrote $MANIFEST ($(list_files | wc -l) files)"
}

verify() {
  [ -f "$MANIFEST" ] || { echo "FAIL: $MANIFEST missing (run ops/manifest.sh)" >&2; exit 1; }
  local rc=0 f h p
  declare -A want
  while read -r h p; do p="${p#\*}"; [ -n "$p" ] && want["$p"]=$h; done < <(grep -v '^#' "$MANIFEST")
  while IFS= read -r f; do
    if [ ! -f "$f" ]; then
      echo "FAIL $f (tracked, missing on disk)"; rc=1
    elif [ -z "${want[$f]:-}" ]; then
      echo "FAIL $f (tracked, not in manifest)"; rc=1
    elif [ "${want[$f]}" != "$(sha256sum "$f" | cut -d' ' -f1)" ]; then
      echo "FAIL $f (hash mismatch)"; rc=1
    fi
    unset "want[$f]"
  done < <(list_files)
  for p in "${!want[@]}"; do echo "FAIL $p (in manifest, not tracked)"; rc=1; done
  [ "$rc" -eq 0 ] && echo "PASS: manifest matches ($(list_files | wc -l) files)"
  exit "$rc"
}

case "${1:-}" in
  "")       regen ;;
  --verify) verify ;;
  *) echo "usage: ops/manifest.sh [--verify]" >&2; exit 2 ;;
esac
