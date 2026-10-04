#!/usr/bin/env bash
# Back up everything needed to restore Sentry:
#   - PostgreSQL (orgs, projects, users, issues, alert rules, DSN keys)
#   - sentry-data volume (uploaded source maps, debug files, attachments)
#   - config (.env, sentry/config.yml, sentry/sentry.conf.py, relay credentials)
# Raw events in ClickHouse are not included: they expire with the retention
# period anyway, and issues/metadata survive via PostgreSQL.
#
# Cron example (daily 03:30):
#   30 3 * * * /opt/central-sentry/scripts/backup.sh >> /var/log/sentry-backup.log 2>&1
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_env
backup_root=${BACKUP_DIR:-./backups}
[[ "$backup_root" = /* ]] || backup_root="$ROOT_DIR/$backup_root"
dest="$backup_root/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dest"

log "Dumping PostgreSQL"
dc exec -T postgres pg_dumpall -U postgres | gzip >"$dest/postgres.sql.gz"

log "Archiving sentry-data volume"
docker run --rm -v sentry-data:/data:ro -v "$dest":/backup alpine \
  tar czf /backup/sentry-data.tar.gz -C /data .

log "Copying config"
tar czf "$dest/config.tar.gz" -C "$ROOT_DIR" .env \
  -C "$UPSTREAM_DIR" .env.custom sentry/config.yml sentry/sentry.conf.py relay/config.yml relay/credentials.json

keep=${BACKUP_KEEP_DAYS:-7}
log "Removing backups older than $keep days"
find "$backup_root" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep" -exec rm -rf {} +

log "Backup written to $dest"
