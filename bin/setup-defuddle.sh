#!/usr/bin/env bash
# setup-defuddle.sh — opt-in installer for defuddle-cli (optional dep).
#
# defuddle strips ads/nav/boilerplate from web pages before wiki-ingest.
# Cuts token usage 40-60% on typical web articles. Fully optional: wiki-ingest
# falls back to raw WebFetch when defuddle is not present.
#
# What this does:
#   1. Check if defuddle binary is already on PATH → report and exit 0
#   2. Check if npm is available (required to install defuddle-cli)
#   3. Run `npm install -g defuddle` and verify the result
#   4. Update .vault-meta/optional-deps-status.json with detection result
#
# Usage:
#   bash bin/setup-defuddle.sh             # install if absent
#   bash bin/setup-defuddle.sh --check     # detect only; no install
#   bash bin/setup-defuddle.sh --force     # reinstall even if present
#
# Exit codes:
#   0 — defuddle present (was already installed or just installed)
#   1 — install failed
#   2 — npm not found (cannot install)
#   3 — --check: defuddle absent (informational, not an error for callers)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="$(dirname "$SCRIPT_DIR")"
META="$VAULT/.vault-meta"
STATUS_FILE="$META/optional-deps-status.json"

CHECK_ONLY=false
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  CHECK_ONLY=true ;;
    --force)  FORCE=true ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERR: unknown flag: $1" >&2
      exit 2
      ;;
  esac
  shift
done

say() { printf '%s\n' "$@"; }
ok()  { printf 'OK   %s\n' "$@"; }
warn(){ printf 'WARN %s\n' "$@" >&2; }
fail(){ printf 'FAIL %s\n' "$@" >&2; }

say "═══ defuddle-cli setup ═══"
say "Vault: $VAULT"
say ""

# ── 1. Detection ─────────────────────────────────────────────────────────────
DEFUDDLE_PATH="$(which defuddle 2>/dev/null || true)"
DEFUDDLE_VERSION=""
if [ -n "$DEFUDDLE_PATH" ]; then
  DEFUDDLE_VERSION="$(defuddle --version 2>/dev/null || echo "unknown")"
fi

_write_status() {
  local present="$1" version="$2" path="$3"
  mkdir -p "$META"
  local ts py_bool
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  py_bool="True"; [ "$present" = false ] && py_bool="False"
  python3 - <<PYEOF
import json, os
status_path = "$STATUS_FILE"
try:
    data = json.loads(open(status_path).read()) if os.path.isfile(status_path) else {}
except Exception:
    data = {}
data["defuddle"] = {
    "present": $py_bool,
    "version": "$version",
    "path": "$path",
    "checked_at": "$ts",
    "install_cmd": "npm install -g defuddle",
    "docs_url": "https://github.com/kepano/defuddle"
}
open(status_path, "w").write(json.dumps(data, indent=2))
PYEOF
}

if [ -n "$DEFUDDLE_PATH" ] && [ "$FORCE" = false ]; then
  ok "defuddle already installed: $DEFUDDLE_PATH (${DEFUDDLE_VERSION})"
  _write_status true "$DEFUDDLE_VERSION" "$DEFUDDLE_PATH"
  say ""
  say "Usage: defuddle https://example.com/article > .raw/articles/slug-\$(date +%Y-%m-%d).md"
  exit 0
fi

if [ "$CHECK_ONLY" = true ]; then
  if [ -n "$DEFUDDLE_PATH" ]; then
    ok "defuddle present: $DEFUDDLE_PATH (${DEFUDDLE_VERSION})"
    _write_status true "$DEFUDDLE_VERSION" "$DEFUDDLE_PATH"
    exit 0
  else
    warn "defuddle not found — run without --check to install"
    _write_status false "" ""
    exit 3
  fi
fi

# ── 2. npm check ─────────────────────────────────────────────────────────────
if ! command -v npm &>/dev/null; then
  fail "npm not found — install Node.js first: https://nodejs.org"
  exit 2
fi
NPM_VERSION="$(npm --version)"
say "npm $NPM_VERSION found"
say ""

# ── 3. Install ───────────────────────────────────────────────────────────────
say "Installing defuddle-cli..."
if npm install -g defuddle; then
  DEFUDDLE_PATH="$(which defuddle 2>/dev/null || true)"
  DEFUDDLE_VERSION="$(defuddle --version 2>/dev/null || echo "unknown")"
  if [ -n "$DEFUDDLE_PATH" ]; then
    ok "defuddle-cli installed: $DEFUDDLE_PATH (${DEFUDDLE_VERSION})"
    _write_status true "$DEFUDDLE_VERSION" "$DEFUDDLE_PATH"
    say ""
    say "Usage: defuddle https://example.com/article > .raw/articles/slug-\$(date +%Y-%m-%d).md"
    say "       bash bin/setup-defuddle.sh --check  # re-run detection"
    exit 0
  else
    fail "npm install succeeded but defuddle not found on PATH"
    _write_status false "" ""
    exit 1
  fi
else
  fail "npm install -g defuddle failed (rc=$?)"
  _write_status false "" ""
  exit 1
fi
