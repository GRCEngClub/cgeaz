#!/usr/bin/env bash
# Guide CI: the lab guides are code, so they get tested like code.
#
# CGE-P shipped guides whose fenced commands were never machine-checked, and learners
# paid for it in paste-and-fail syntax errors. This script extracts every fenced code
# block from the guides and validates it:
#
#   ```hcl / ```terraform  ->  terraform fmt -check   (parses the HCL; fails on syntax)
#   ```bash                ->  bash -n                (syntax check)
#                              plus `shellcheck -s bash -S error` when installed
#                              (error severity only: guide snippets legitimately omit
#                              set -e, quoting, and shebangs that a real script needs)
#
# It also verifies that every relative markdown link points at a file that exists.
# Other fence languages (kusto, plain output excerpts) are documentation, not code
# we can execute, and are skipped.
#
# Run from anywhere; it locates the repo root relative to itself.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FAILURES=0

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# --- 1. Extract fenced blocks per file, one directory per block ---------------

extract_blocks() { # $1 = markdown file (relative to ROOT)
  awk -v outdir="$WORKDIR/blocks" -v src="$1" '
    BEGIN { n = 0; inblock = 0 }
    # A fence may be indented up to 3 spaces (e.g. inside a markdown list).
    /^ {0,3}```/ {
      if (!inblock) {
        lang = $0
        sub(/^ *```/, "", lang)
        sub(/[ \t\r]+$/, "", lang)
        indent = index($0, "`") - 1
        inblock = 1
        n += 1
        buf = ""
        startline = NR
        next
      } else {
        if (lang == "bash" || lang == "hcl" || lang == "terraform") {
          safe = src
          gsub(/[\/]/, "__", safe)
          dir = outdir "/" safe "__" n "_" lang
          system("mkdir -p " dir)
          file = dir "/block" (lang == "bash" ? ".sh" : ".tf")
          printf "%s", buf > file
          close(file)
          print src ":" startline ":" lang ":" file
        }
        inblock = 0
        next
      }
    }
    inblock {
      line = $0
      if (indent > 0) sub("^ {1," indent "}", "", line)
      buf = buf line "\n"
    }
  ' "$ROOT/$1"
}

GUIDE_FILES=()
while IFS= read -r f; do
  GUIDE_FILES+=("$f")
done < <(cd "$ROOT" && ls README.md docs/*.md labs/*/README.md 2>/dev/null)

mkdir -p "$WORKDIR/blocks"
MANIFEST="$WORKDIR/manifest.txt"
: > "$MANIFEST"
for f in "${GUIDE_FILES[@]}"; do
  extract_blocks "$f" >> "$MANIFEST"
done

echo "Extracted $(wc -l < "$MANIFEST" | tr -d ' ') validatable blocks from ${#GUIDE_FILES[@]} markdown files."

# --- 2. Validate each block ---------------------------------------------------

HAVE_SHELLCHECK=0
command -v shellcheck > /dev/null 2>&1 && HAVE_SHELLCHECK=1
[ "$HAVE_SHELLCHECK" -eq 0 ] && echo "note: shellcheck not installed; bash blocks get bash -n only."

while IFS=: read -r src line lang file; do
  where="$src:$line (\`\`\`$lang block)"
  case "$lang" in
    bash)
      if ! bash -n "$file" 2> "$WORKDIR/err.txt"; then
        fail "$where: bash -n rejected it: $(head -3 "$WORKDIR/err.txt")"
        continue
      fi
      if [ "$HAVE_SHELLCHECK" -eq 1 ]; then
        if ! shellcheck -s bash -S error "$file" > "$WORKDIR/err.txt" 2>&1; then
          fail "$where: shellcheck (error severity): $(grep -m2 'SC[0-9]' "$WORKDIR/err.txt")"
          continue
        fi
      fi
      echo "ok: $where"
      ;;
    hcl | terraform)
      if ! terraform fmt -check "$file" > "$WORKDIR/err.txt" 2>&1; then
        fail "$where: terraform fmt -check: $(head -3 "$WORKDIR/err.txt")"
        continue
      fi
      echo "ok: $where"
      ;;
  esac
done < "$MANIFEST"

# --- 3. Relative markdown links must resolve ----------------------------------

for f in "${GUIDE_FILES[@]}"; do
  dir="$ROOT/$(dirname "$f")"
  while IFS= read -r link; do
    case "$link" in
      http://* | https://* | mailto:* | \#*) continue ;;
    esac
    target="${link%%#*}"
    [ -z "$target" ] && continue
    if [ ! -e "$dir/$target" ]; then
      fail "$f: broken relative link -> $link"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$ROOT/$f" | sed -E 's/^\]\(//; s/\)$//')
done

# --- Result --------------------------------------------------------------------

if [ "$FAILURES" -gt 0 ]; then
  echo
  echo "$FAILURES guide check(s) failed."
  exit 1
fi
echo
echo "All guide blocks and links check out."
