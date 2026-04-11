# MyFlix

Self-hosted media server for movies, series, anime, music, and books.

```
Seerr (request UI)
  |
  v
Radarr (Movies) + Sonarr (TV/Anime) + Lidarr (Music) + Readarr (Books)
  |
  v
Prowlarr (indexer manager) ---> FlareSolverr (Cloudflare bypass)
  |
  v
qBittorrent (download client)
  |
  v
Jellyfin (media server) <--- Bazarr (subtitles)
Kavita (book reader)
```

## Quick Start

### 1. Prepare the server

Install Docker on your Linux server:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in
```

### 2. Set up storage

Mount your storage drive (or use existing disk space for ephemeral mode):

```bash
# Find your user/group IDs
id $USER
# Example: uid=1000(user) gid=1000(user)

# Run the setup script (creates all folders + verifies hardlinks)
sudo bash scripts/setup-server.sh /media/storage 1000 1000
```

### 3. Configure

```bash
cp .env.example .env
# Edit .env with your values:
#   - PUID/PGID from step 2
#   - TZ (your timezone)
#   - DATA_ROOT (where you mounted storage)
#   - CLEANUP_MODE: "ephemeral" (<50 GB) or "persistent" (dedicated drive)
```

### 4. Start the stack

```bash
# Phase 0 — ephemeral mode (9 services, for limited storage)
docker compose up -d

# Phase 1 — full mode (12 services, when you have a dedicated drive)
docker compose --profile full up -d
```

### 5. Configure services

Open each web UI in your browser and configure in this order:

| # | Service | URL | What to do |
|---|---------|-----|------------|
| 1 | qBittorrent | `http://SERVER_IP:8085` | Change default password (`docker logs qbittorrent`), set download categories |
| 2 | Prowlarr | `http://SERVER_IP:9696` | Add indexers, add FlareSolverr proxy (`http://flaresolverr:8191`) |
| 3 | Radarr | `http://SERVER_IP:7878` | Root folder: `/data/media/movies`, download client: `http://qbittorrent:8085` |
| 4 | Sonarr | `http://SERVER_IP:8989` | Root folders: `/data/media/series` + `/data/media/anime` |
| 5 | Bazarr | `http://SERVER_IP:6767` | Connect to Sonarr (`http://sonarr:8989`) and Radarr (`http://radarr:7878`) |
| 6 | Jellyfin | `http://SERVER_IP:8096` | Create libraries: Movies, Series, Anime, + "Now Downloading" |
| 7 | Seerr | `http://SERVER_IP:5055` | Connect to Jellyfin (`http://jellyfin:8096`), Radarr, Sonarr |

**Phase 1 only (when storage is available):**

| # | Service | URL | What to do |
|---|---------|-----|------------|
| 8 | Lidarr | `http://SERVER_IP:8686` | Root folder: `/data/media/music` |
| 9 | Readarr | `http://SERVER_IP:8787` | Root folder: `/data/media/books` |
| 10 | Kavita | `http://SERVER_IP:5000` | Add library: `/data/books` |

> All inter-service connections use container names (e.g., `http://radarr:7878`), not IP addresses.

### 6. Set up auto-cleanup

```bash
# Install the cleanup cron job (runs daily at 3 AM)
(crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1") | crontab -
```

## Streaming While Downloading

To start watching a movie/show before it finishes downloading:

1. In qBittorrent, right-click the torrent and enable **"Download in sequential order"**
2. Also enable **"Download first and last pieces first"** (helps with MP4 files)
3. Wait for ~10-15% to download
4. Open Jellyfin, go to the **"Now Downloading"** library, and start playing

> Download speed must exceed the video bitrate or playback will buffer.

## Ephemeral vs Persistent Mode

| | Ephemeral (Phase 0) | Persistent (Phase 1) |
|---|---|---|
| **Storage needed** | <50 GB | 4-8 TB recommended |
| **How it works** | Download, watch, auto-delete after 48h | Download, keep in library permanently |
| **File handling** | Move (no hardlinks) | Hardlinks (space-efficient) |
| **Quality** | 720p recommended | 1080p/4K |
| **Cleanup** | Aggressive (media + downloads) | Conservative (downloads only) |

To switch modes, change `CLEANUP_MODE` in `.env` and re-enable hardlinks in Radarr/Sonarr settings.

## Updating Containers

Watchtower auto-updates all containers daily. To update manually:

```bash
docker compose pull && docker compose up -d
```

## Viewing Logs

```bash
docker logs <container-name>        # View logs
docker logs -f <container-name>     # Follow in real time
docker compose ps                   # Check all container status
```

## Folder Structure

```
/media/storage/
├── media/
│   ├── movies/       <- Radarr
│   ├── series/       <- Sonarr
│   ├── anime/        <- Sonarr
│   ├── music/        <- Lidarr (Phase 1)
│   └── books/        <- Readarr (Phase 1)
├── downloads/
│   └── torrents/
│       ├── incomplete/
│       ├── movies/
│       ├── series/
│       ├── anime/
│       ├── music/
│       └── books/
└── appdata/          <- Container configs
```
