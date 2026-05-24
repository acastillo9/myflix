# MyFlix Troubleshooting Guide

Common issues and solutions for the MyFlix media server stack.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Permission Issues](#permission-issues)
- [Service Won't Start](#service-wont-start)
- [Cannot Connect to Services](#cannot-connect-to-services)
- [Hardlink Issues](#hardlink-issues)
- [Download Issues](#download-issues)
- [Data Loss Recovery](#data-loss-recovery)
- [Performance Issues](#performance-issues)

---

## Installation Issues

### Error: ".env file not found"

**Problem**: The setup script or init scripts cannot find the configuration file.

**Solution**:
```bash
cp .env.example .env
nano .env  # Edit with your values
```

### Error: "DATA_ROOT directory does not exist"

**Problem**: The storage path specified in `.env` doesn't exist.

**Solution**:
1. Check if your drive is mounted:
   ```bash
   df -h
   ```
2. Create and mount the directory:
   ```bash
   sudo mkdir -p /media/storage
   sudo mount /dev/sdX1 /media/storage  # Replace with your device
   ```
3. Update `.env` with the correct path:
   ```bash
   DATA_ROOT=/media/storage
   ```

### Error: "This script must be run as root"

**Solution**:
```bash
sudo bash scripts/setup-server.sh
```

---

## Permission Issues

### Error: "Permission denied" when accessing media files

**Problem**: File ownership doesn't match the PUID/PGID in `.env`.

**Solution**:
1. Check current ownership:
   ```bash
   ls -la /media/storage/media/
   ```
2. Fix ownership:
   ```bash
   sudo chown -R 1000:1000 /media/storage
   sudo chmod -R 2775 /media/storage
   ```

### Error: "Cannot write to download directory"

**Problem**: qBittorrent or *arr apps can't write to downloads.

**Solution**:
```bash
# Check if downloads directory exists
ls -la /media/storage/downloads/

# Fix permissions
sudo chown -R 1000:1000 /media/storage/downloads
sudo chmod -R 2775 /media/storage/downloads

# Restart containers
docker compose restart
```

---

## Service Won't Start

### Container keeps restarting

**Check logs**:
```bash
docker logs <container-name>
```

**Common causes**:

1. **Port conflict**: Another service is using the same port
   ```bash
   # Check what's using the port
   sudo netstat -tlnp | grep 7878
   
   # Change port in .env
   RADARR_PORT=7879
   ```

2. **Missing configuration**: Appdata directory not created
   ```bash
   sudo bash scripts/setup-server.sh
   ```

3. **Database corruption**: Config file is corrupted
   ```bash
   # Backup and recreate
   mv /media/storage/appdata/radarr/config.xml /media/storage/appdata/radarr/config.xml.bak
   docker restart radarr
   ```

### Service won't start with "depends_on" errors

**Problem**: Docker Compose v2 syntax for depends_on with health conditions requires newer Docker version.

**Solution**:
- Update Docker and Docker Compose:
  ```bash
  sudo apt update && sudo apt upgrade docker-compose-plugin
  ```
- Or use the original docker-compose.yml without depends_on conditions

---

## Cannot Connect to Services

### "Connection refused" when accessing web UI

**Check if container is running**:
```bash
docker ps | grep radarr
```

**Check service health**:
```bash
# Radarr
curl http://localhost:7878/ping

# Sonarr
curl http://localhost:8989/ping

# Check with healthcheck script
bash scripts/healthcheck.sh status
```

### Services work locally but not from other devices

**Problem**: Firewall blocking ports.

**Solution**:
```bash
# Check firewall status
sudo ufw status

# Allow MyFlix ports
sudo ufw allow 8096/tcp  # Jellyfin
sudo ufw allow 7878/tcp  # Radarr
sudo ufw allow 8989/tcp  # Sonarr
# ... etc
```

---

## Hardlink Issues

### Error: "Hardlinks FAILED"

**Problem**: downloads and media directories are on different filesystems.

**Verify**:
```bash
df /media/storage/downloads /media/storage/media
```

Both should show the same device. If different, hardlinks won't work.

**Solution**:
1. Ensure both directories are on the same partition
2. Or use copy mode instead of hardlinks in Radarr/Sonarr settings
3. Re-run setup script after fixing paths

### Downloads imported as copies instead of hardlinks

**Check hardlink count**:
```bash
ls -li /media/storage/downloads/torrents/movies/
ls -li /media/storage/media/movies/

# Files with same inode number are hardlinked
```

**Fix in Radarr/Sonarr**:
1. Go to Settings → Media Management
2. Enable "Hardlinks"
3. Ensure "Import using Hardlinks" is checked

---

## Download Issues

### qBittorrent shows "Stalled"

**Possible causes**:
- No seeders available
- Port not forwarded
- VPN/proxy blocking connections

**Solutions**:
1. Check port forwarding on your router
2. Verify firewall allows torrent port:
   ```bash
   sudo ufw allow 6881/tcp
   sudo ufw allow 6881/udp
   ```
3. Test with a known-good torrent

### Indexers not working in Prowlarr

**Check FlareSolverr**:
```bash
# Test FlareSolverr
curl http://localhost:8191
```

**Verify proxy settings in Prowlarr**:
1. Settings → Indexers → Proxy
2. Should show FlareSolverr at `http://flaresolverr:8191`

### Downloads complete but don't import

**Check**:
1. Download client is added to Radarr/Sonarr
2. Category is set correctly (movies/series/anime)
3. Root folder is accessible
4. Permissions allow writing

**Debug**:
```bash
# Check Radarr logs
docker logs radarr | grep -i "import"

# Check folder permissions
ls -la /media/media/downloads/torrents/movies/
```

---

## Data Loss Recovery

### Configuration lost after container recreation

**Problem**: Appdata not persisted properly.

**Recovery**:
1. **If you have backups**:
   ```bash
   sudo bash scripts/backup-restore.sh restore
   # Follow prompts to select backup
   ```

2. **If no backups**:
   - Reconfigure services manually
   - Set up automated backups immediately:
     ```bash
     sudo bash scripts/backup-restore.sh schedule
     ```

### Accidentally deleted media files

**Recovery**:
1. Check if files are in downloads folder (hardlinked copies)
2. Check trash/recycle bin if enabled in Radarr/Sonarr
3. Restore from backups if available

### Database corruption

**Fix**:
```bash
# Stop the service
docker stop radarr

# Backup corrupted database
cd /media/storage/appdata/radarr
mv radarr.db radarr.db.corrupt.$(date +%Y%m%d)

# Restore from backup (if available)
cp backups/radarr.db.20240115 ./radarr.db

# Or start fresh (will need to reconfigure)
docker start radarr
```

---

## Performance Issues

### Jellyfin transcoding is slow

**Solutions**:
1. Enable hardware acceleration in Jellyfin settings
2. Ensure Jellyfin container has access to GPU (add to docker-compose.yml)
3. Pre-transcode popular content

### Services running slowly or using too much memory

**Check resource usage**:
```bash
docker stats
```

**Adjust limits in docker-compose.yml**:
```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 512M
```

**Restart services**:
```bash
docker compose restart
```

### Disk space issues

**Check usage**:
```bash
df -h /media/storage
du -sh /media/storage/* | sort -h
```

**Clean up**:
```bash
# Run cleanup manually
bash scripts/cleanup-downloads.sh

# Check for large logs
ls -lh /media/storage/logs/

# Remove old backups
ls -lh /media/storage/backups/
```

---

## Getting Help

If you're still stuck:

1. **Check logs first**:
   ```bash
   docker logs <container-name>
   ```

2. **Run healthcheck**:
   ```bash
   bash scripts/healthcheck.sh status
   ```

3. **Verify configuration**:
   ```bash
   bash scripts/setup-server.sh  # Validates paths and permissions
   ```

4. **Check service-specific documentation**:
   - [Jellyfin Docs](https://jellyfin.org/docs/)
   - [Radarr Wiki](https://wiki.servarr.com/radarr)
   - [Sonarr Wiki](https://wiki.servarr.com/sonarr)
   - [Prowlarr Wiki](https://wiki.servarr.com/prowlarr)

5. **Community support**:
   - r/jellyfin
   - r/radarr
   - r/sonarr
   - r/selfhosted
