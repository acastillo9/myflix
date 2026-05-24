# MyFlix — Agent Notes

Self-hosted media server stack using Docker Compose. Arr-suite + Jellyfin + qBittorrent.

## Commands

```bash
# Phase 0 (ephemeral, 9 services) — for limited storage
docker compose up -d

# Phase 1 (full, 12 services) — requires dedicated drive
docker compose --profile full up -d

# View logs
docker logs <container-name>
docker compose ps

# Update containers (Watchtower auto-updates daily)
docker compose pull && docker compose up -d
```

## Configuration Flow

Services must be configured in this order (use container names, not IPs):

1. **qBittorrent** (`:8085`) — get password from `docker logs qbittorrent`
2. **Prowlarr** (`:9696`) — add indexers, add FlareSolverr proxy `http://flaresolverr:8191`
3. **Radarr** (`:7878`) — root `/data/media/movies`, download client `http://qbittorrent:8085`
4. **Sonarr** (`:8989`) — root `/data/media/series` + `/data/media/anime`
5. **Bazarr** (`:6767`) — connect to Sonarr (`http://sonarr:8989`) + Radarr
6. **Jellyfin** (`:8096`) — create libraries (Movies, Series, Anime, "Now Downloading")
7. **Seerr** (`:5055`) — connect Jellyfin (`http://jellyfin:8096`), Radarr, Sonarr

Phase 1 only (with `--profile full`): Lidarr (`:8686`), Readarr (`:8787`), Kavita (`:5000`)

## Key Files

| File | Purpose |
|------|---------|
| `.env` | All configuration (copied from `.env.example`) |
| `scripts/setup-server.sh` | One-time server setup — creates folder structure, verifies hardlinks |
| `scripts/cleanup-downloads.sh` | Daily cleanup cron job (reads `.env` for `CLEANUP_MODE`) |

## Two Modes

| Mode | Services | Storage | Behavior |
|------|----------|---------|----------|
| **ephemeral** | 9 | <50 GB | Auto-delete media after 48h (streaming cache) |
| **persistent** | 12 | 4-8 TB | Hardlinks, keep library, delete downloads after import |

Set `CLEANUP_MODE` in `.env`. Cleanup script uses hardlink count to verify media was imported before deleting downloads.

## Gotchas

- **Hardlinks required** — `DATA_ROOT` must be a single ext4 filesystem. Setup script verifies this.
- **Setup script is idempotent** — safe to re-run for permissions/structure fixes.
- **Port conflicts** — all ports configurable in `.env` (defaults: Jellyfin 8096, Seerr 5055, Radarr 7878, Sonarr 8989, qBittorrent 8085, Prowlarr 9696, Bazarr 6767)
- **Inter-service URLs** — use container names (`http://radarr:7878`), not `localhost` or IPs.
- **Cleanup cron** — install with: `0 3 * * * /path/to/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1`
