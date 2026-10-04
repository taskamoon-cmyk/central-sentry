#!/usr/bin/env bash
# Upgrade to a new getsentry/self-hosted release.
# Usage: scripts/upgrade.sh 26.10.0
#
# Upstream has "hard stops": some versions must be installed in sequence.
# Check https://develop.sentry.dev/self-hosted/releases/ before jumping far.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

new_version=${1:?usage: $0 <self-hosted release tag, e.g. 26.10.0>}
load_env

git -C "$UPSTREAM_DIR" fetch --quiet --tags origin
git -C "$UPSTREAM_DIR" rev-parse --verify --quiet "refs/tags/$new_version" >/dev/null \
  || die "Unknown self-hosted release: $new_version"

log "Taking a backup before upgrading $SENTRY_VERSION -> $new_version"
"$ROOT_DIR/scripts/backup.sh"

set_env_var "$ROOT_DIR/.env" SENTRY_VERSION "$new_version"
log "Stopping Sentry"
dc down
exec "$ROOT_DIR/scripts/install.sh"
