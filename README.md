# MyFlix

A self-hosted media server stack for movies, TV series, anime, music, and books — fully managed with Docker Compose and bash scripts. No application code to build or maintain; just configuration files and operational scripts.

---

## Table of Contents

- [Architecture](#architecture)
- [Service Overview](#service-overview)
- [Operating Modes](#operating-modes)
- [Prerequisites](#prerequisites)
- [Step-by-Step Setup Guide](#step-by-step-setup-guide)
  - [1. Install Docker](#1-install-docker)
  - [2. Clone the Repository](#2-clone-the-repository)
  - [3. Configure Environment](#3-configure-environment)
  - [4. Prepare Storage](#4-prepare-storage)
  - [5. Start the Stack](#5-start-the-stack)
  - [6. Configure Each Service](#6-configure-each-service)
  - [7. Automate Maintenance](#7-automate-maintenance)
- [HTTPS with Traefik](#https-with-traefik)
- [Folder Structure](#folder-structure)
- [Environment Variables Reference](#environment-variables-reference)
- [Scripts Reference](#scripts-reference)
- [Day-to-Day Operations](#day-to-day-operations)
- [Streaming While Downloading](#streaming-while-downloading)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
Seerr (request UI)              :5055
  │
  ├── Radarr (movies)           :7878
  ├── Sonarr (TV/anime)         :8989
  ├── Lidarr (music)*           :8686
  └── Readarr (books)*          :8787
        │
        └── Prowlarr (indexers) :9696
              └── FlareSolverr  :8191  ← Cloudflare bypass
                    │
                    └── qBittorrent :8085  ← download client

Jellyfin (streaming)            :8096
  └── Bazarr (subtitles)        :6767

Kavita (book reader)*           :5000
Watchtower (auto-updater)       — no port
Traefik (HTTPS proxy)*          :80 / :443
```

`*` = `--profile full` only (Phase 1). Traefik = `--profile traefik`.

All services talk to each other **by container name** over the `myflix` Docker bridge network (e.g., `http://radarr:7878`). Never use `localhost` or IP addresses for inter-service URLs.

---

## Service Overview

| Service | Container | Default Port | Purpose |
|---------|-----------|-------------|---------|
| Jellyfin | `jellyfin` | 8096 | Media streaming server |
| Jellyseerr | `seerr` | 5055 | Request interface for users |
| Radarr | `radarr` | 7878 | Automated movie management |
| Sonarr | `sonarr` | 8989 | Automated TV/anime management |
| Lidarr *(full)* | `lidarr` | 8686 | Automated music management |
| Readarr *(full)* | `readarr` | 8787 | Automated book management |
| Prowlarr | `prowlarr` | 9696 | Indexer manager for all *arr apps |
| FlareSolverr | `flaresolverr` | 8191 | Bypasses Cloudflare-protected indexers |
| qBittorrent | `qbittorrent` | 8085 | Torrent download client |
| Bazarr | `bazarr` | 6767 | Automatic subtitle downloading |
| Kavita *(full)* | `kavita` | 5000 | Web-based book/comic reader |
| Watchtower | `watchtower` | — | Automatically updates containers daily |
| Traefik *(traefik)* | `traefik` | 80/443 | HTTPS reverse proxy with Let's Encrypt |

---

## Operating Modes

The stack supports two modes controlled by `CLEANUP_MODE` in `.env`:

| | **Ephemeral** (Phase 0) | **Persistent** (Phase 1) |
|---|---|---|
| **Docker profile** | *(default — no profile)* | `--profile full` |
| **Services** | 9 core services | 12 services (+ Lidarr, Readarr, Kavita) |
| **Storage needed** | < 50 GB | 4–8 TB recommended |
| **Media files** | Auto-deleted after `CLEANUP_MAX_AGE_HOURS` (default 48h) | Kept permanently via hardlinks |
| **Download files** | Deleted after age threshold | Deleted only after hardlink count ≥ 2 (library copy exists) |
| **Quality** | 720p recommended | 1080p / 4K |
| **Use case** | Watch then discard; no dedicated drive | Permanent personal library |

To switch modes, change `CLEANUP_MODE` in `.env` and update the import mode in Radarr/Sonarr settings (Settings → Media Management).

---

## Prerequisites

- A Linux server (Ubuntu/Debian recommended; any distro with Docker works)
- Docker Engine **20.10+** and Docker Compose plugin **v2**
- At least 4 GB RAM (8 GB recommended for transcoding)
- Internet access for pulling images and torrents

### Minimum System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB |
| OS disk | 20 GB | 50 GB |
| Media storage | 50 GB (ephemeral) | 4+ TB (persistent) |

---

## Step-by-Step Setup Guide

### 1. Install Docker

```bash
# Install Docker Engine (official one-liner)
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group so you don't need sudo for every command
sudo usermod -aG docker $USER

# Log out and back in for the group change to take effect
# Verify it worked:
docker ps
```

### 2. Clone the Repository

```bash
git clone https://github.com/yourusername/myflix.git
cd myflix
```

### 3. Configure Environment

```bash
# Copy the example config
cp .env.example .env
```

Open `.env` in your editor and fill in the required values:

```bash
nano .env   # or vim, or any editor you prefer
```

**Key settings to change:**

```bash
# Find your user and group IDs — these ensure containers write files as you
id $USER
# Example output: uid=1000(andres) gid=1000(andres)
# → Set PUID=1000 and PGID=1000

# Your timezone — find yours at:
# https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=America/New_York

# Where your media storage lives (single ext4 filesystem for hardlinks)
DATA_ROOT=/media/storage

# Where container configs/databases are stored (must survive rebuilds)
APPDATA_ROOT=/media/storage/appdata

# ephemeral = watch-and-delete; persistent = keep library forever
CLEANUP_MODE=ephemeral
```

> **Important:** All ports are configurable. If a port is already in use on your server, change the corresponding `_PORT` variable (e.g., `RADARR_PORT=7879`) and run `docker compose up -d` to apply.

### 4. Prepare Storage

#### Option A — Use Existing Disk Space (Ephemeral Mode)

If you're using space on your existing disk (no dedicated drive):

```bash
# Create the storage directory
sudo mkdir -p /media/storage

# Run the setup script — it reads .env automatically
sudo bash scripts/setup-server.sh
```

The script will warn you that `DATA_ROOT` is on the root filesystem. Type `y` to continue.

#### Option B — Mount a Dedicated Drive (Persistent Mode, Recommended)

```bash
# Find your drive
lsblk

# Format if needed (WARNING: this erases the drive)
sudo mkfs.ext4 /dev/sdX1    # Replace sdX1 with your device

# Create mount point and mount
sudo mkdir -p /media/storage
sudo mount /dev/sdX1 /media/storage

# Add to /etc/fstab for automatic mounting on boot
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdX1) /media/storage ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Update .env to use the mounted path
# DATA_ROOT=/media/storage
# CLEANUP_MODE=persistent

# Run the setup script
sudo bash scripts/setup-server.sh
```

**What `setup-server.sh` does:**

1. Loads configuration from `.env`
2. Verifies `DATA_ROOT` exists and is accessible
3. Creates the complete folder tree under `DATA_ROOT`:
   - `media/{movies,series,anime,music,books}/`
   - `downloads/torrents/{incomplete,movies,series,anime,music,books}/`
   - `appdata/{jellyfin,seerr,radarr,sonarr,...}/`
   - `backups/`
4. Sets correct ownership (`PUID:PGID`) and permissions (`2775` with setgid)
5. Runs a hardlink verification test to ensure downloads and media are on the same filesystem

> If the hardlink test fails, Radarr/Sonarr will fall back to copying files, doubling your disk usage.

### 5. Start the Stack

```bash
# Phase 0 — ephemeral mode (9 core services, no dedicated drive)
docker compose up -d

# Phase 1 — full mode (12 services, dedicated drive)
docker compose --profile full up -d

# With HTTPS via Traefik (see HTTPS section below)
docker compose --profile traefik up -d
docker compose --profile full --profile traefik up -d
```

Verify everything started:

```bash
docker compose ps
```

All containers should show `Up` status. Services with health checks will show `(healthy)` after ~30 seconds.

```bash
# Watch logs to confirm no errors
docker compose logs -f
```

### 6. Configure Each Service

Services must be configured **in this order** because each one depends on the previous. All web UIs are accessible at `http://YOUR_SERVER_IP:PORT`.

---

#### 6.1 qBittorrent — Download Client

**URL:** `http://SERVER_IP:8085`

1. **Find the temporary password:**
   ```bash
   docker logs qbittorrent 2>&1 | grep -i "temporary password"
   ```
   The first login uses `admin` / `<temporary password from logs>`.

2. **Change the password** immediately: Settings → Web UI → Authentication → Change password.

3. **Configure download categories** (this is critical for Radarr/Sonarr to route files correctly):
   - Go to the Categories panel on the left sidebar
   - Add categories matching the folder names: `movies`, `series`, `anime`, `music`, `books`
   - Set each category's save path to `/data/downloads/torrents/<category>`

4. **Configure the incomplete directory:**
   - Settings → Downloads → Default Save Path: `/data/downloads/torrents`
   - Enable "Keep incomplete torrents in:" → `/data/downloads/torrents/incomplete`

5. **Enable sequential download (optional but recommended for streaming):**
   - Settings → BitTorrent → Enable "Sequential Download" by default

---

#### 6.2 Prowlarr — Indexer Manager

**URL:** `http://SERVER_IP:9696`

Prowlarr manages all torrent indexers in one place and syncs them automatically to Radarr/Sonarr.

1. **Set up FlareSolverr proxy** (needed for Cloudflare-protected indexers):
   - Settings → Indexers → Add Proxy
   - Name: `FlareSolverr`
   - URL: `http://flaresolverr:8191`
   - Test and Save

2. **Add indexers:**
   - Indexers → Add Indexer
   - Search for your preferred indexers (e.g., 1337x, RARBG alternatives, etc.)
   - For Cloudflare-protected ones, assign the FlareSolverr proxy

3. **Connect to *arr apps** (Prowlarr will push indexers automatically):
   - Settings → Apps → Add Application
   - Add Radarr: URL = `http://radarr:7878`, get API key from Radarr's Settings → General
   - Add Sonarr: URL = `http://sonarr:8989`
   - Add Lidarr: URL = `http://lidarr:8686` *(Phase 1 only)*
   - Add Readarr: URL = `http://readarr:8787` *(Phase 1 only)*

---

#### 6.3 Radarr — Movie Manager

**URL:** `http://SERVER_IP:7878`

1. **Add the download client:**
   - Settings → Download Clients → Add
   - Type: `qBittorrent`
   - Host: `qbittorrent`, Port: `8085`
   - Username and password (the one you set in step 6.1)
   - Category: `movies`
   - Test and Save

2. **Add root folder:**
   - Settings → Media Management → Root Folders → Add
   - Path: `/data/media/movies`

3. **Configure import settings:**
   - Settings → Media Management
   - Enable "Use Hardlinks instead of Copy" (for persistent mode)
   - Set your preferred naming format

4. **Add quality profiles:**
   - Settings → Quality
   - Adjust for your mode: 720p for ephemeral, 1080p/4K for persistent

---

#### 6.4 Sonarr — TV Series & Anime Manager

**URL:** `http://SERVER_IP:8989`

1. **Add the download client** (same as Radarr, but Category: `series`)

2. **Add root folders:**
   - `/data/media/series` — for regular TV shows
   - `/data/media/anime` — for anime (use a separate Sonarr instance or separate root folder with different naming)

3. **Configure import settings** (same hardlinks recommendation as Radarr)

4. **Anime-specific setup:**
   - Settings → Profiles → Add a dedicated "Anime" quality profile
   - Use categories: `anime` for qBittorrent

---

#### 6.5 Bazarr — Automatic Subtitles

**URL:** `http://SERVER_IP:6767`

1. **Connect to Sonarr:**
   - Settings → Sonarr → Enable
   - Address: `sonarr`, Port: `8989`
   - API key from Sonarr's Settings → General
   - Test and Save

2. **Connect to Radarr:**
   - Settings → Radarr → Enable
   - Address: `radarr`, Port: `7878`
   - API key from Radarr's Settings → General

3. **Add subtitle providers:**
   - Settings → Providers → Add
   - Recommended: OpenSubtitles, Subscene, or Addic7ed
   - Configure your preferred languages

---

#### 6.6 Jellyfin — Media Streaming Server

**URL:** `http://SERVER_IP:8096`

1. **Initial wizard:** Create admin account, select your preferred language and metadata providers.

2. **Add media libraries:**

   | Library Name | Type | Folder |
   |---|---|---|
   | Movies | Movies | `/data/media/movies` |
   | TV Shows | Shows | `/data/media/series` |
   | Anime | Shows | `/data/media/anime` |
   | Music | Music | `/data/media/music` *(full only)* |
   | Now Downloading | Movies/Shows | `/data/downloads/torrents` |

   > The "Now Downloading" library lets you stream a torrent while it's still downloading (see [Streaming While Downloading](#streaming-while-downloading)).

3. **Configure transcoding:**
   - Dashboard → Playback → Transcoding
   - Set FFmpeg path to `/usr/lib/jellyfin-ffmpeg/ffmpeg` (pre-configured in the container)
   - Enable hardware acceleration if your server has a GPU (Intel QSV, NVIDIA NVENC, VA-API)

4. **Create user accounts** for family members via Dashboard → Users.

---

#### 6.7 Jellyseerr — Request Interface

**URL:** `http://SERVER_IP:5055`

Seerr gives users a Netflix-like interface to request new movies and shows.

1. **Initial setup wizard → Connect to Jellyfin:**
   - Jellyfin URL: `http://jellyfin:8096`
   - Sign in with your Jellyfin admin account
   - Select the Jellyfin users who should have access

2. **Add Radarr:**
   - Settings → Radarr → Add Radarr Server
   - Hostname: `radarr`, Port: `7878`
   - API key from Radarr → Settings → General
   - Default Profile, Quality Profile, Root Folder: `/data/media/movies`
   - Test and Save

3. **Add Sonarr:**
   - Settings → Sonarr → Add Sonarr Server
   - Hostname: `sonarr`, Port: `8989`
   - API key from Sonarr → Settings → General
   - Configure default profiles and root folder
   - Test and Save

4. **Configure request settings:**
   - Settings → General → Default Permissions
   - Decide whether users auto-approve or need admin approval

---

#### 6.8 Phase 1 Only — Lidarr, Readarr, Kavita

**Lidarr** (`http://SERVER_IP:8686`) — Music:
- Add download client: qBittorrent, Category: `music`
- Root folder: `/data/media/music`
- Add indexers via Prowlarr sync

**Readarr** (`http://SERVER_IP:8787`) — Books:
- Add download client: qBittorrent, Category: `books`
- Root folder: `/data/media/books`
- Add indexers via Prowlarr sync

**Kavita** (`http://SERVER_IP:5000`) — Book Reader:
- Initial setup: create admin account
- Add library → `/data/books`
- Kavita will scan and index all epub/cbz/pdf files

---

### 7. Automate Maintenance

#### Automated Backups (Recommended — do this before anything else breaks)

```bash
# Install daily backup cron job (runs at 2:00 AM)
sudo bash scripts/backup-restore.sh schedule

# Verify it's installed
crontab -l
```

Backups are stored in `DATA_ROOT/backups/` as `.tar.gz` archives. Old backups are pruned after `BACKUP_RETENTION_DAYS` days (default: 30).

#### Health Monitoring

```bash
# Install cron job that checks all services every 5 minutes
bash scripts/healthcheck.sh schedule

# To receive email alerts, set HEALTHCHECK_ALERT_EMAIL in .env
# Requires 'mail', 'sendmail', or 'msmtp' on the host
```

#### Media Cleanup Cron

```bash
# Install daily cleanup job (runs at 3 AM)
(crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1") | crontab -
```

#### Log Rotation

```bash
# Set up logrotate for MyFlix log files
sudo bash scripts/setup-logrotate.sh
```

---

## HTTPS with Traefik

`docker-compose.override.yml` is **automatically loaded** by Docker Compose and adds Traefik as an HTTPS reverse proxy. When Traefik is active, all services get subdomains with automatic Let's Encrypt certificates.

### Setup

1. **Point DNS at your server.** For each service, create an A record:
   ```
   jellyfin.yourdomain.com  →  SERVER_IP
   seerr.yourdomain.com     →  SERVER_IP
   radarr.yourdomain.com    →  SERVER_IP
   sonarr.yourdomain.com    →  SERVER_IP
   prowlarr.yourdomain.com  →  SERVER_IP
   bazarr.yourdomain.com    →  SERVER_IP
   qbittorrent.yourdomain.com → SERVER_IP
   ```
   *(and lidarr, readarr, kavita if using Phase 1)*

2. **Configure `.env`:**
   ```bash
   DOMAIN=yourdomain.com
   TRAEFIK_ACME_EMAIL=your@email.com
   ```

3. **Open ports 80 and 443** on your server's firewall:
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

4. **Start with the `traefik` profile:**
   ```bash
   # Phase 0 + Traefik
   docker compose --profile traefik up -d

   # Phase 1 + Traefik
   docker compose --profile full --profile traefik up -d
   ```

Services will be available at `https://jellyfin.yourdomain.com`, `https://seerr.yourdomain.com`, etc. HTTP requests are automatically redirected to HTTPS.

---

## Folder Structure

```
DATA_ROOT/  (default: /media/storage)
├── media/
│   ├── movies/           ← Radarr imports here
│   ├── series/           ← Sonarr imports here
│   ├── anime/            ← Sonarr (anime) imports here
│   ├── music/            ← Lidarr imports here (Phase 1)
│   └── books/            ← Readarr imports here (Phase 1)
├── downloads/
│   └── torrents/
│       ├── incomplete/   ← Active downloads (never touched by cleanup)
│       ├── movies/       ← Completed movie downloads
│       ├── series/       ← Completed TV downloads
│       ├── anime/        ← Completed anime downloads
│       ├── music/        ← Completed music downloads (Phase 1)
│       └── books/        ← Completed book downloads (Phase 1)
├── appdata/              ← All container configs and databases
│   ├── jellyfin/
│   │   ├── config/
│   │   └── cache/
│   ├── seerr/
│   ├── radarr/
│   ├── sonarr/
│   ├── lidarr/
│   ├── readarr/
│   ├── kavita/
│   ├── prowlarr/
│   ├── bazarr/
│   └── qbittorrent/
├── backups/              ← Compressed appdata backups
├── logs/                 ← Healthcheck and cleanup logs
└── letsencrypt/          ← Traefik TLS certificates (if using HTTPS)
```

> **Critical:** `downloads/` and `media/` **must be on the same filesystem** for hardlinks to work. The setup script verifies this.

> **Critical:** `appdata/` contains all service databases and configs. If you lose this directory, all services revert to factory defaults. Back it up regularly.

---

## Environment Variables Reference

All configuration lives in `.env`. Copy from `.env.example` to get started.

| Variable | Default | Description |
|---|---|---|
| `PUID` | `1000` | User ID that containers run as. Get from `id $USER`. |
| `PGID` | `1000` | Group ID that containers run as. Get from `id $USER`. |
| `TZ` | `America/New_York` | Timezone. See [tz database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). |
| `DATA_ROOT` | `/media/storage` | Root of media storage — downloads and media must be here. |
| `APPDATA_ROOT` | `/media/storage/appdata` | Where container configs and databases are stored. |
| `CLEANUP_MODE` | `ephemeral` | `ephemeral` = auto-delete old media; `persistent` = keep library. |
| `CLEANUP_MAX_AGE_HOURS` | `48` | Files older than this are eligible for deletion. |
| `JELLYFIN_PORT` | `8096` | Jellyfin web UI port. |
| `SEERR_PORT` | `5055` | Jellyseerr web UI port. |
| `RADARR_PORT` | `7878` | Radarr web UI port. |
| `SONARR_PORT` | `8989` | Sonarr web UI port. |
| `LIDARR_PORT` | `8686` | Lidarr web UI port. *(Phase 1)* |
| `READARR_PORT` | `8787` | Readarr web UI port. *(Phase 1)* |
| `KAVITA_PORT` | `5000` | Kavita book reader port. *(Phase 1)* |
| `PROWLARR_PORT` | `9696` | Prowlarr web UI port. |
| `BAZARR_PORT` | `6767` | Bazarr web UI port. |
| `QBIT_WEBUI_PORT` | `8085` | qBittorrent web UI port. |
| `QBIT_TORRENT_PORT` | `6881` | qBittorrent BitTorrent protocol port (TCP + UDP). Forward this on your router for better speeds. |
| `FLARESOLVERR_PORT` | `8191` | FlareSolverr API port. |
| `WATCHTOWER_POLL_INTERVAL` | `86400` | How often Watchtower checks for container updates (seconds). 86400 = daily. |
| `BACKUP_RETENTION_DAYS` | `30` | How many days of backups to keep before pruning. |
| `HEALTHCHECK_ALERT_EMAIL` | *(empty)* | Email address for service failure alerts. Requires a mail client on the host. |
| `DOMAIN` | `yourdomain.com` | Domain for Traefik HTTPS. *(traefik profile)* |
| `TRAEFIK_ACME_EMAIL` | `your@email.com` | Email for Let's Encrypt certificate registration. *(traefik profile)* |

---

## Scripts Reference

### `scripts/setup-server.sh`

One-time server preparation. Creates the full folder tree, sets permissions, and verifies hardlinks work.

```bash
sudo bash scripts/setup-server.sh
```

- Reads configuration from `.env` — **create `.env` before running**
- Idempotent: safe to run multiple times
- Fails with a clear message if `DATA_ROOT` doesn't exist or hardlinks fail

---

### `scripts/cleanup-downloads.sh`

Removes completed downloads (and media in ephemeral mode) to reclaim disk space.

```bash
bash scripts/cleanup-downloads.sh
```

**Behavior by mode:**

- **`ephemeral`:** Deletes any file in `downloads/torrents/` **and** `media/` older than `CLEANUP_MAX_AGE_HOURS`. Never touches `incomplete/`.
- **`persistent`:** Deletes completed downloads only when:
  - The file is older than `CLEANUP_MAX_AGE_HOURS`
  - The file's hardlink count is ≥ 2 (meaning it's been imported to the library)
  - Never touches the media library

Typically run via cron at 3 AM:
```bash
0 3 * * * /path/to/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1
```

---

### `scripts/healthcheck.sh`

Polls each service's health endpoint and reports status.

```bash
bash scripts/healthcheck.sh              # Run check once
bash scripts/healthcheck.sh status       # Detailed table of all services
bash scripts/healthcheck.sh schedule     # Install cron (every 5 minutes)
bash scripts/healthcheck.sh unschedule   # Remove cron
```

Set `HEALTHCHECK_ALERT_EMAIL` in `.env` to receive email alerts when services go down.

---

### `scripts/backup-restore.sh`

Backs up and restores the `APPDATA_ROOT` directory (all service configs and databases).

```bash
sudo bash scripts/backup-restore.sh backup      # Create backup now
sudo bash scripts/backup-restore.sh list        # List available backups
sudo bash scripts/backup-restore.sh restore     # Interactive restore
sudo bash scripts/backup-restore.sh schedule    # Install daily cron (2 AM)
sudo bash scripts/backup-restore.sh unschedule  # Remove cron
```

- Backups are saved to `DATA_ROOT/backups/myflix-backup-TIMESTAMP.tar.gz`
- Restore automatically stops containers, creates a safety backup of current state, then restores and restarts
- Old backups are pruned automatically after `BACKUP_RETENTION_DAYS` days

---

### `scripts/setup-logrotate.sh`

Configures logrotate to rotate MyFlix log files in `DATA_ROOT/logs/`.

```bash
sudo bash scripts/setup-logrotate.sh
```

---

## Day-to-Day Operations

### Check Stack Status

```bash
docker compose ps                  # All containers and their health
bash scripts/healthcheck.sh status # Human-readable status table
```

### View Logs

```bash
docker logs radarr                 # Last N lines
docker logs -f radarr              # Follow in real time
docker compose logs -f             # Follow all services at once
```

### Update All Containers

Watchtower handles this automatically daily. To update manually:

```bash
docker compose pull && docker compose up -d
```

### Restart a Service

```bash
docker compose restart radarr      # Restart one service
docker compose restart             # Restart all services
```

### Stop and Start the Stack

```bash
docker compose stop                # Stop all (keeps containers)
docker compose start               # Start again
docker compose down                # Stop and remove containers (data safe)
docker compose up -d               # Recreate and start
```

### Create a Manual Backup

```bash
sudo bash scripts/backup-restore.sh backup
```

### Run Cleanup Manually

```bash
bash scripts/cleanup-downloads.sh
```

### Check Disk Usage

```bash
df -h /media/storage
du -sh /media/storage/* | sort -h
docker stats                        # Live CPU/memory usage per container
```

### Port Conflict Resolution

If a port is already in use:

```bash
# Find what's using port 7878
sudo ss -tlnp | grep 7878

# Change the port in .env
RADARR_PORT=7879

# Apply the change
docker compose up -d radarr
```

---

## Streaming While Downloading

You can start watching a movie or episode before it finishes downloading:

1. In **qBittorrent**, right-click the active torrent:
   - Enable **"Download in sequential order"**
   - Enable **"Download first and last pieces first"** (helps MP4 seekability)

2. Wait for **~10–15%** to download (enough buffer to start playback)

3. Open **Jellyfin** → Browse the **"Now Downloading"** library → Play

> Download speed must exceed the video's bitrate or playback will buffer. A 720p file at ~2 Mbps needs at least 2 Mbps sustained download speed.

---

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for detailed solutions to common problems including:

- Permission errors
- Hardlink failures
- Services not starting
- Indexers not working
- Downloads not importing
- Data recovery

**Quick diagnostics:**

```bash
# Check all service health
bash scripts/healthcheck.sh status

# Check a specific service
docker logs radarr | tail -50

# Verify folder structure and permissions
sudo bash scripts/setup-server.sh   # Idempotent — safe to re-run

# Verify hardlinks are working
stat -c '%h %n' /media/storage/media/movies/**/*.mkv | head
# Link count of 2+ means the file is hardlinked from downloads
```

**Community resources:**
- [Jellyfin Documentation](https://jellyfin.org/docs/)
- [Radarr Wiki](https://wiki.servarr.com/radarr)
- [Sonarr Wiki](https://wiki.servarr.com/sonarr)
- [Prowlarr Wiki](https://wiki.servarr.com/prowlarr)
- r/selfhosted, r/jellyfin, r/radarr
