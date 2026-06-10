#!/usr/bin/env bash
# Verifies every local href/src in *.html resolves to a real file, and
# every anchor fragment (#id) exists in its target page.
# Usage: bash scripts/check-links.sh   (exits non-zero on any dead link)
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

for page in *.html; do
  while IFS= read -r ref; do
    case "$ref" in http://*|https://*|mailto:*) continue ;; esac
    case "$ref" in *'${'*) continue ;; esac   # JS template literal, not a real link

    path="${ref%%#*}"
    frag=""
    case "$ref" in *#*) frag="${ref#*#}" ;; esac
    path="${path%%\?*}"

    # file existence (empty path = same-page anchor)
    target="$page"
    if [ -n "$path" ]; then
      if [ ! -e "$path" ]; then
        echo "✗ $page → $ref  (missing file: $path)"
        fail=1
        continue
      fi
      target="$path"
    fi

    # anchor existence (only check inside html targets)
    if [ -n "$frag" ] && [[ "$target" == *.html ]]; then
      if ! grep -q "id=\"$frag\"" "$target"; then
        echo "✗ $page → $ref  (missing anchor #$frag in $target)"
        fail=1
      fi
    fi
  done < <(grep -oE '(href|src)="[^"]+"' "$page" | sed -E 's/^(href|src)="//; s/"$//' | sort -u)
done

# _redirects targets must exist as pages (clean URLs map to <name>.html)
if [ -f _redirects ]; then
  while read -r _from to _status; do
    case "$to" in /*) f="${to#/}";; *) continue;; esac
    [ -z "$f" ] && f="index"
    if [ ! -e "$f" ] && [ ! -e "$f.html" ]; then
      echo "✗ _redirects → $to  (no $f or $f.html)"
      fail=1
    fi
  done < <(grep -vE '^\s*(#|$)' _redirects)
fi

if [ "$fail" -eq 0 ]; then echo "✓ all local links and anchors resolve"; fi
exit $fail
