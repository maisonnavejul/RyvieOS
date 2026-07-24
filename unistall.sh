#!/usr/bin/env bash
# =====================================================
# Ryvie OS — Uninstall script
# =====================================================
# Usage:
#   sudo bash uninstall.sh                  → uninstalls Ryvie, KEEPS /data (user data)
#   sudo bash uninstall.sh --purge-data     → uninstalls AND destroys /data (IRREVERSIBLE)
#   sudo bash uninstall.sh --purge-docker   → also removes Docker packages
#   sudo bash uninstall.sh --yes            → no interactive confirmation
# Flags can be combined.
# =====================================================

set -u

PURGE_DATA=0
PURGE_DOCKER=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --purge-data)   PURGE_DATA=1 ;;
    --purge-docker) PURGE_DOCKER=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

DATA_ROOT="/data"
DATA_IMG="/data.img"
RYVIE_DIR="/opt/Ryvie"
EXEC_USER="${SUDO_USER:-ryvie}"
[ "$EXEC_USER" = "root" ] && EXEC_USER="ryvie"

echo ""
echo "====================================================="
echo " Ryvie OS uninstall"
echo "====================================================="
echo ""
echo "  Application code : $RYVIE_DIR              → REMOVED"
echo "  PM2 services     : backend/frontend        → REMOVED"
echo "  Docker containers: Ryvie apps              → STOPPED AND REMOVED"
echo "  NetBird          : disconnected and disabled"
if [ "$PURGE_DATA" -eq 1 ]; then
  echo "  /data            : ⚠️  DESTROYED (--purge-data) — IRREVERSIBLE"
else
  echo "  /data            : ✅ KEPT (photos, files, configs)"
fi
if [ "$PURGE_DOCKER" -eq 1 ]; then
  echo "  Docker packages  : REMOVED (--purge-docker)"
else
  echo "  Docker packages  : kept"
fi
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ "$PURGE_DATA" -eq 1 ]; then
    read -p "⚠️  ALL DATA in /data will be LOST. Type 'DESTROY' to confirm: " CONFIRM
    [ "$CONFIRM" = "DESTROY" ] || { echo "Aborted."; exit 1; }
  else
    read -p "Confirm Ryvie uninstall? (yes/no): " CONFIRM
    [ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }
    # Offer /data deletion (interactive equivalent of --purge-data)
    read -p "Also delete ALL data in /data (photos, files, configs)? (yes/no): " CONFIRM_DATA
    if [ "$CONFIRM_DATA" = "yes" ]; then
      read -p "⚠️  IRREVERSIBLE. Type 'DESTROY' to confirm: " CONFIRM2
      if [ "$CONFIRM2" = "DESTROY" ]; then
        PURGE_DATA=1
        echo "→ /data will be DESTROYED."
      else
        echo "→ Wrong confirmation: /data will be KEPT."
      fi
    else
      echo "→ /data will be kept."
    fi
  fi
fi

echo ""
echo "----------------------------------------------------"
echo "1/7 Stopping PM2 services"
echo "----------------------------------------------------"
if command -v pm2 >/dev/null 2>&1; then
  sudo -u "$EXEC_USER" pm2 delete all 2>/dev/null || true
  sudo -u "$EXEC_USER" pm2 save --force 2>/dev/null || true
  # Remove PM2 autostart (systemd service pm2-<user>)
  sudo pm2 unstartup systemd -u "$EXEC_USER" --hp "$(getent passwd "$EXEC_USER" | cut -d: -f6)" 2>/dev/null || true
  sudo systemctl disable "pm2-$EXEC_USER" 2>/dev/null || true
  echo "✅ PM2 services removed."
else
  echo "ℹ️ PM2 not installed, nothing to do."
fi

echo ""
echo "----------------------------------------------------"
echo "2/7 Stopping and removing Docker containers"
echo "----------------------------------------------------"
if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
  # Bring down known compose stacks cleanly (apps + ldap)
  for compose in "$DATA_ROOT"/apps/*/docker-compose.yml \
                 "$DATA_ROOT"/apps/*/*/docker-compose.yml \
                 "$DATA_ROOT"/config/ldap/docker-compose.yml; do
    [ -f "$compose" ] || continue
    echo "  ↓ docker compose down: $(dirname "$compose")"
    sudo docker compose -f "$compose" down --remove-orphans 2>/dev/null || true
  done
  # Then any remaining container (keycloak, caddy, etc.)
  REMAINING=$(sudo docker ps -aq)
  if [ -n "$REMAINING" ]; then
    sudo docker stop $REMAINING 2>/dev/null || true
    sudo docker rm -f $REMAINING 2>/dev/null || true
  fi
  echo "✅ Containers stopped and removed."

  # Purge orphaned Docker networks. WITHOUT this, a ghost bridge keeps the
  # old subnet (e.g. 172.20.0.0/24): on the NEXT install, the new network
  # gets the same subnet, the host route points to the dead bridge →
  # containers unreachable from the host → install.sh loops forever on
  # "Waiting for the OpenLDAP service".
  sudo docker network prune -f 2>/dev/null || true
  # Leftover kernel bridges the daemon lost track of (network prune no
  # longer sees them): delete them directly.
  for br in $(ip -br link show type bridge 2>/dev/null | awk '{print $1}' | grep '^br-'); do
    sudo ip link delete "$br" 2>/dev/null || true
  done
  echo "✅ Orphaned Docker networks purged."
  if [ "$PURGE_DATA" -eq 1 ]; then
    # Volumes/images are useless once /data is destroyed
    sudo docker system prune -af --volumes 2>/dev/null || true
    echo "✅ Docker images and volumes purged."
  fi
else
  echo "ℹ️ Docker not available, nothing to do."
fi

echo ""
echo "----------------------------------------------------"
echo "3/7 NetBird"
echo "----------------------------------------------------"
if command -v netbird >/dev/null 2>&1; then
  sudo netbird down 2>/dev/null || true
  sudo systemctl disable --now netbird 2>/dev/null || true
  # Remove the /var/lib/netbird → /data/netbird symlink
  [ -L /var/lib/netbird ] && sudo rm -f /var/lib/netbird
  echo "✅ NetBird disconnected and disabled (package kept, identity in $DATA_ROOT/netbird)."
else
  echo "ℹ️ NetBird not installed."
fi

echo ""
echo "----------------------------------------------------"
echo "4/7 Removing application code"
echo "----------------------------------------------------"
if [ -d "$RYVIE_DIR" ]; then
  sudo rm -rf "$RYVIE_DIR"
  echo "✅ $RYVIE_DIR removed."
else
  echo "ℹ️ $RYVIE_DIR absent."
fi
# Auto-install service, if any
sudo systemctl disable ryvie-install.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ryvie-install.service /root/run-install.sh

echo ""
echo "----------------------------------------------------"
echo "5/7 Avahi hostname"
echo "----------------------------------------------------"
if [ -f /etc/avahi/avahi-daemon.conf ] && grep -q '^host-name=ryvie' /etc/avahi/avahi-daemon.conf; then
  sudo sed -i 's/^host-name=ryvie/#host-name=/' /etc/avahi/avahi-daemon.conf
  sudo systemctl restart avahi-daemon 2>/dev/null || true
  echo "✅ mDNS hostname 'ryvie.local' removed."
else
  echo "ℹ️ Nothing to do."
fi

echo ""
echo "----------------------------------------------------"
echo "6/7 /data"
echo "----------------------------------------------------"
if [ "$PURGE_DATA" -eq 1 ]; then
  # Docker/containerd point to /data → stop them and point them back to /var/lib
  sudo systemctl stop docker containerd 2>/dev/null || true
  if [ -f /etc/docker/daemon.json ] && command -v jq >/dev/null 2>&1; then
    sudo sh -c 'jq "del(.\"data-root\")" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json' || true
  fi
  [ -f /etc/containerd/config.toml ] && sudo sed -i '/^root = "\/data\/containerd"/d' /etc/containerd/config.toml

  if findmnt -no TARGET "$DATA_ROOT" >/dev/null 2>&1; then
    sudo umount -l "$DATA_ROOT" 2>/dev/null || true
  fi
  # Remove the /data fstab entry (partition or loopback image)
  sudo sed -i "\|[[:space:]]${DATA_ROOT}[[:space:]]|d" /etc/fstab
  # Delete the loopback image if it exists
  if [ -f "$DATA_IMG" ]; then
    sudo rm -f "$DATA_IMG"
    echo "✅ Loopback image $DATA_IMG deleted."
  fi
  # Clear the leftover mount point
  sudo rm -rf "${DATA_ROOT:?}" 2>/dev/null || true
  echo "✅ /data destroyed."
  echo "ℹ️ If /data was a dedicated partition/RAID, the disk is NOT reformatted (unmounted only)."
  echo "ℹ️ Appliance reinstall: recreate a btrfs /data on the RAID (mkfs + mount + fstab)"
  echo "   BEFORE running install.sh, otherwise it will fall back to a loopback image (vps mode)."
  if [ "$PURGE_DOCKER" -ne 1 ]; then
    sudo systemctl start containerd docker 2>/dev/null || true
  fi
else
  echo "✅ /data fully kept (photos, files, directory, configs)."
  echo "   → Reinstalling via install.sh will pick these data up again."
fi

echo ""
echo "----------------------------------------------------"
echo "7/7 Docker packages"
echo "----------------------------------------------------"
if [ "$PURGE_DOCKER" -eq 1 ]; then
  sudo systemctl disable --now docker containerd 2>/dev/null || true
  sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
  echo "✅ Docker packages removed."
else
  echo "ℹ️ Docker packages kept."
fi

echo ""
echo "====================================================="
echo "✅ Ryvie uninstall complete."
if [ "$PURGE_DATA" -ne 1 ]; then
  echo "   Your data is intact in $DATA_ROOT."
fi
echo "   Intentionally not removed: user '$EXEC_USER', sudoers,"
echo "   Node.js/npm/PM2, Redis, NetBird package."
echo "====================================================="
