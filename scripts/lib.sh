#!/usr/bin/env bash
# Shared helpers for the central-sentry scripts.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="$ROOT_DIR/self-hosted"
UPSTREAM_REPO="https://github.com/getsentry/self-hosted.git"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

load_env() {
  [[ -f "$ROOT_DIR/.env" ]] || die "No .env found. Run: cp .env.example .env && edit it"
  set -a
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
  set +a
  : "${SENTRY_VERSION:?SENTRY_VERSION is required in .env}"
  : "${SENTRY_DOMAIN:?SENTRY_DOMAIN is required in .env}"
  : "${ACME_EMAIL:?ACME_EMAIL is required in .env}"
  [[ "$SENTRY_DOMAIN" != "sentry.example.com" ]] || die "Set SENTRY_DOMAIN in .env to your real domain"
}

# Set KEY=VALUE in a dotenv file (replace if present, append otherwise).
set_env_var() {
  local file=$1 key=$2 value=$3
  touch "$file"
  if grep -q "^${key}=" "$file"; then
    local tmp
    tmp=$(mktemp)
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$file" >"$tmp"
    cat "$tmp" >"$file" && rm -f "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

# Set a top-level `key: value` in Sentry's config.yml (value is written verbatim).
set_yml_key() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp)
  awk -v k="$key" -v v="$value" '
    index($0, k ":") == 1 { print k ": " v; found=1; next }
    { print }
    END { if (!found) print k ": " v }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file" && rm -f "$tmp"
}

# docker compose against the upstream checkout, honouring .env.custom.
dc() {
  (cd "$UPSTREAM_DIR" && docker compose --env-file .env --env-file .env.custom "$@")
}

dc_proxy() {
  (cd "$ROOT_DIR/proxy" && docker compose --env-file "$ROOT_DIR/.env" "$@")
}
