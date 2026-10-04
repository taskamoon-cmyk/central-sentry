# Central Sentry

A self-hosted [Sentry](https://sentry.io) instance that collects errors and performance data from all our websites and apps on our own server.

```
  Web / Mobile / Backend apps  ── HTTPS (DSN) ──▶  Caddy (TLS, :443)
                                                       │
                                                       ▼ 127.0.0.1:9000
                                         getsentry/self-hosted (docker compose)
                                 nginx → web / relay → kafka → snuba → clickhouse
                                                 postgres · redis · taskworkers
```

## Why this setup

- **Official [getsentry/self-hosted](https://github.com/getsentry/self-hosted)**: we don't write Sentry's docker-compose ourselves. The upstream release is pinned in `.env` (`SENTRY_VERSION`). This repo only holds our config and operations scripts, so upgrades stay easy.
- **Caddy** sits in front and gets and renews the HTTPS certificate on its own. Sentry is only exposed on `127.0.0.1:9000`.
- **One server, one organization, one project per product.** Every site and app gets its own DSN.

## Server requirements

| Profile | RAM | CPU | Disk | What you get |
|---|---|---|---|---|
| `feature-complete` | at least 16GB (32GB recommended) | 4 cores | 50GB+ SSD | Errors, Performance/Tracing, Session Replay, Profiling, Crons, Uptime |
| `errors-only` | ~8GB | 2 cores | 30GB+ SSD | Errors only |

- Linux x86_64, Docker 19.03.6 or newer, Docker Compose 2.32.2 or newer, git, bash 4.4 or newer
- A domain such as `sentry.company.com` whose A record points to the server
- Ports 80 and 443 open (80 is needed to issue the certificate)

> If the server is weaker than this, see the lighter alternative at the end of this file.

## Installation

```bash
git clone <this-repo> /opt/central-sentry && cd /opt/central-sentry
cp .env.example .env
nano .env                    # SENTRY_DOMAIN, ACME_EMAIL, SMTP_*, COMPOSE_PROFILES
./scripts/install.sh         # first run takes ~10–20 minutes
./scripts/create-admin.sh admin@company.com
```

Then open `https://sentry.company.com` and:
1. Create an organization (for example `company`).
2. Create a team per group (web, mobile, backend).
3. Create a project per product with the right platform. Its DSN is shown in **Project Settings → Client Keys**.

Whenever you change `.env`, run `./scripts/install.sh` again. It is idempotent.

## Connecting sites and apps

Full SDK setup for each platform (React/Next.js, Node, Python/Django, PHP/Laravel, Android, iOS, Flutter, React Native), source map upload, and release tagging are in [`docs/sdk-integration.md`](docs/sdk-integration.md).

The short version: just point the SDK at our DSN:
```js
Sentry.init({ dsn: "https://<key>@sentry.company.com/<project-id>", environment: "production" });
```

## Day-to-day operations

| Task | Command |
|---|---|
| Container status | `./scripts/status.sh` |
| Manual backup | `./scripts/backup.sh` |
| Upgrade | `./scripts/upgrade.sh 26.10.0` |
| Logs | `cd self-hosted && docker compose logs -f web relay` |
| Restart | `cd self-hosted && docker compose restart` |

### Daily backup
```cron
30 3 * * * /opt/central-sentry/scripts/backup.sh >> /var/log/sentry-backup.log 2>&1
```
A backup contains PostgreSQL (users, projects, issues, alerts, DSNs), the `sentry-data` volume (source maps, debug files), and the config files. Copy the `backups/` folder to another server or to object storage too.

### Upgrades
- Upstream ships a new release every month. Read the [releases](https://github.com/getsentry/self-hosted/releases) page before upgrading.
- Some versions are **hard stops**: you must install them one at a time and can't skip past them ([list](https://develop.sentry.dev/self-hosted/releases/)).
- `upgrade.sh` takes a backup first and then installs the new version.

## Recommendations

- **Sample rate**: in production, start `tracesSampleRate` at 0.1–0.2 and `replaysSessionSampleRate` at 0.0–0.1. Otherwise ClickHouse and disk fill up quickly.
- **Rate limits**: set a rate limit on each DSN key in **Client Keys** so one noisy app can't take the whole server down.
- **Alerts**: send alerts to email, Slack, or a webhook (Telegram/Mattermost through a small bridge).
- **Ad-blockers**: on web, use the SDK `tunnel` option so ad-blockers don't block requests to the Sentry domain.
- **Monitor Sentry itself**: watch disk and RAM on the server. ClickHouse and Kafka are the heaviest parts.
- **Firewall**: only 80/443 (and SSH) should be open. Nothing else should be exposed.

## Lighter alternative: GlitchTip

If you can't give the server 16GB of RAM, [GlitchTip](https://glitchtip.com) is a light open-source option that is **compatible with the Sentry SDKs** (only 4 containers, about 1GB RAM). It covers errors plus basic performance and uptime, but it has no Session Replay or Profiling. You can migrate later just by changing the DSN; app code stays the same.
