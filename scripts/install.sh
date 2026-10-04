#!/usr/bin/env bash
# Install (or re-apply config to) the central self-hosted Sentry.
# Idempotent: safe to re-run after editing .env.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_env

command -v docker >/dev/null || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose v2 plugin is not installed"
command -v git >/dev/null || die "git is not installed"

# 1. Fetch the pinned upstream release --------------------------------------
if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
  log "Cloning getsentry/self-hosted $SENTRY_VERSION"
  git clone --quiet "$UPSTREAM_REPO" "$UPSTREAM_DIR"
fi
log "Checking out self-hosted $SENTRY_VERSION"
git -C "$UPSTREAM_DIR" fetch --quiet --tags origin
git -C "$UPSTREAM_DIR" -c advice.detachedHead=false checkout --quiet "refs/tags/$SENTRY_VERSION"

# 2. Generate persistent secrets once ---------------------------------------
if [[ -z "${LAUNCHPAD_RPC_SHARED_SECRET:-}" ]]; then
  LAUNCHPAD_RPC_SHARED_SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  set_env_var "$ROOT_DIR/.env" LAUNCHPAD_RPC_SHARED_SECRET "$LAUNCHPAD_RPC_SHARED_SECRET"
fi

# 3. Upstream .env overrides --------------------------------------------------
log "Writing self-hosted/.env.custom"
# Start from upstream defaults so image tags always match the checked-out release.
cp "$UPSTREAM_DIR/.env" "$UPSTREAM_DIR/.env.custom"
custom="$UPSTREAM_DIR/.env.custom"
set_env_var "$custom" COMPOSE_PROFILES "${COMPOSE_PROFILES:-feature-complete}"
set_env_var "$custom" SENTRY_EVENT_RETENTION_DAYS "${SENTRY_EVENT_RETENTION_DAYS:-90}"
set_env_var "$custom" SENTRY_TASKWORKER_CONCURRENCY "${SENTRY_TASKWORKER_CONCURRENCY:-4}"
# Only reachable through the Caddy proxy, never directly from outside.
set_env_var "$custom" SENTRY_BIND "127.0.0.1:9000"
set_env_var "$custom" SENTRY_MAIL_HOST "$SENTRY_DOMAIN"
set_env_var "$custom" LAUNCHPAD_RPC_SHARED_SECRET "$LAUNCHPAD_RPC_SHARED_SECRET"

# 4. Run the upstream installer (migrations, volumes, secret key, ...) ------
log "Running upstream install.sh (this takes a while the first time)"
(cd "$UPSTREAM_DIR" && ./install.sh --skip-user-creation --no-report-self-hosted-issues)

# 5. Apply our settings to the generated Sentry config ----------------------
yml="$UPSTREAM_DIR/sentry/config.yml"
py="$UPSTREAM_DIR/sentry/sentry.conf.py"

log "Configuring $yml"
set_yml_key "$yml" system.url-prefix "'https://$SENTRY_DOMAIN'"
if [[ -n "${SMTP_HOST:-}" ]]; then
  set_yml_key "$yml" mail.backend "'smtp'"
  set_yml_key "$yml" mail.host "'$SMTP_HOST'"
  set_yml_key "$yml" mail.port "${SMTP_PORT:-587}"
  set_yml_key "$yml" mail.username "'${SMTP_USERNAME:-}'"
  set_yml_key "$yml" mail.password "'${SMTP_PASSWORD:-}'"
  set_yml_key "$yml" mail.use-tls "${SMTP_USE_TLS:-true}"
fi
set_yml_key "$yml" mail.from "'${SMTP_FROM:-sentry@$SENTRY_DOMAIN}'"

log "Configuring $py"
begin='# >>> central-sentry managed block >>>'
end='# <<< central-sentry managed block <<<'
tmp=$(mktemp)
awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$py" >"$tmp"
cat >>"$tmp" <<PY
$begin
# Behind Caddy (TLS termination). Edit .env and re-run scripts/install.sh instead of editing here.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SOCIAL_AUTH_REDIRECT_IS_HTTPS = True
CSRF_TRUSTED_ORIGINS = ["https://$SENTRY_DOMAIN"]
$end
PY
cat "$tmp" >"$py" && rm -f "$tmp"

# 6. Start everything -------------------------------------------------------
log "Starting Sentry"
dc up -d --wait

log "Starting HTTPS proxy for $SENTRY_DOMAIN"
dc_proxy up -d

cat <<MSG

Sentry is up at https://$SENTRY_DOMAIN

Next steps:
  * Create the first admin:   ./scripts/create-admin.sh you@company.com
  * Schedule daily backups:   see README (cron + scripts/backup.sh)
  * Connect your apps:        docs/sdk-integration.md
MSG
