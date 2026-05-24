# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

MyFlix is a self-hosted media server stack managed entirely via Docker Compose and bash scripts. There is no application code to build or test — the project consists of configuration files (`docker-compose.yml`, `.env`) and operational scripts.

## Stack Commands

```bash
# Phase 0 — ephemeral mode (9 services, limited storage)
docker compose up -d

# Phase 1 — full mode (12 services, dedicated drive)
docker compose --profile full up -d

# Traefik HTTPS reverse proxy (combine with full if needed)
docker compose --profile traefik up -d
docker compose --profile full --profile traefik up -d

# Check status and logs
docker compose ps
docker logs <container-name>
docker logs -f <container-name>           # Follow in real time

# Update all containers
docker compose pull && docker compose up -d

# Run cleanup manually
bash scripts/cleanup-downloads.sh

# Run healthcheck
bash scripts/healthcheck.sh status

# Backup / restore appdata
sudo bash scripts/backup-restore.sh backup
sudo bash scripts/backup-restore.sh restore
sudo bash scripts/backup-restore.sh list
```

## Initial Setup (on a new server)

```bash
cp .env.example .env       # Then edit .env with PUID, PGID, TZ, DATA_ROOT
sudo bash scripts/setup-server.sh    # Creates folder structure, verifies hardlinks
docker compose up -d
bash scripts/init/init-all.sh        # Declaratively configures services via their APIs
```

Then configure services via browser in this order: qBittorrent → Prowlarr → Radarr → Sonarr → Bazarr → Jellyfin → Seerr.

## Architecture

```
Seerr (request UI)         :5055
  → Radarr (movies)        :7878
  → Sonarr (TV/anime)      :8989
  → Lidarr (music)*        :8686
  → Readarr (books)*       :8787
  ↓
Prowlarr (indexers)        :9696
  → FlareSolverr (CF bypass) :8191
  ↓
qBittorrent (downloads)    :8085

Jellyfin (streaming)       :8096
  ← Bazarr (subtitles)     :6767

Kavita (book reader)*      :5000
Watchtower (auto-updater)
Traefik (HTTPS proxy)*     :80/:443
```

`*` = `--profile full` only; Traefik = `--profile traefik`

All services communicate by **container name** over the `myflix` bridge network (e.g., `http://radarr:7878`). Never use `localhost` or IP addresses for inter-service URLs.

## Key Files

| File | Purpose |
|------|---------|
| `.env` | All runtime configuration — copy from `.env.example` |
| `docker-compose.yml` | Core stack definition (Phase 0 + Phase 1 profiles) |
| `docker-compose.override.yml` | Traefik HTTPS extension — loaded automatically by docker compose |
| `scripts/setup-server.sh` | One-time server prep: creates `DATA_ROOT` folder tree, verifies hardlinks, sets permissions. Reads `.env`. Idempotent. |
| `scripts/cleanup-downloads.sh` | Daily cron cleanup — behavior depends on `CLEANUP_MODE` in `.env` |
| `scripts/backup-restore.sh` | Backs up/restores `APPDATA_ROOT` (container configs/DBs) |
| `scripts/healthcheck.sh` | Polls each service and optionally emails on failure |
| `scripts/init/` | Per-service API init scripts (configure Radarr, Sonarr, Prowlarr, Bazarr via their REST APIs) |

## Two Operating Modes

`CLEANUP_MODE` in `.env` controls behavior:

| | `ephemeral` (Phase 0) | `persistent` (Phase 1) |
|---|---|---|
| Storage | <50 GB | 4–8 TB dedicated drive |
| Media files | Auto-deleted after `CLEANUP_MAX_AGE_HOURS` (default 48h) | Kept permanently via hardlinks |
| Downloads | Deleted after age threshold | Deleted only after hardlink count ≥ 2 (imported to library) |
| Quality | 720p recommended | 1080p/4K |

## Critical Constraints

- **Hardlinks require a single filesystem**: `DATA_ROOT/downloads` and `DATA_ROOT/media` must be on the same ext4 partition. `setup-server.sh` verifies this with a test file. If hardlinks fail, Radarr/Sonarr will fall back to copies, doubling disk usage.
- **`APPDATA_ROOT` must survive container rebuilds**: It stores all service databases and configs. Back it up with `backup-restore.sh schedule` before making changes.
- **`setup-server.sh` reads `.env`** — create `.env` before running it.
- **Port conflicts**: All ports are configurable in `.env`. If a port is in use, change the env var (e.g., `RADARR_PORT=7879`) and run `docker compose up -d`.
- **`docker-compose.override.yml`** is auto-loaded by docker compose. It adds the `traefik` profile — activating it requires `ENABLE_TRAEFIK=true` and valid `DOMAIN`/`TRAEFIK_ACME_EMAIL` in `.env`.

## Cron Jobs

```bash
# Daily media/download cleanup at 3 AM
0 3 * * * /path/to/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1

# Set up with backup-restore.sh
sudo bash scripts/backup-restore.sh schedule

# Set up healthcheck every 5 minutes
bash scripts/healthcheck.sh schedule

# Set up log rotation
sudo bash scripts/setup-logrotate.sh
```
