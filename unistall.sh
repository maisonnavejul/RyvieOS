#!/usr/bin/env bash
# =====================================================
# Ryvie OS — Script de désinstallation
# =====================================================
# Usage :
#   sudo bash uninstall.sh                  → désinstalle Ryvie, CONSERVE /data (données utilisateur)
#   sudo bash uninstall.sh --purge-data     → désinstalle ET détruit /data (IRRÉVERSIBLE)
#   sudo bash uninstall.sh --purge-docker   → supprime aussi les paquets Docker
#   sudo bash uninstall.sh --yes            → pas de confirmation interactive
# Les flags sont cumulables.
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
    *) echo "Option inconnue: $arg"; exit 1 ;;
  esac
done

DATA_ROOT="/data"
DATA_IMG="/data.img"
RYVIE_DIR="/opt/Ryvie"
EXEC_USER="${SUDO_USER:-ryvie}"
[ "$EXEC_USER" = "root" ] && EXEC_USER="ryvie"

echo ""
echo "====================================================="
echo " Désinstallation de Ryvie OS"
echo "====================================================="
echo ""
echo "  Code applicatif  : $RYVIE_DIR              → SUPPRIMÉ"
echo "  Services PM2     : backend/frontend        → SUPPRIMÉS"
echo "  Conteneurs Docker: apps Ryvie              → ARRÊTÉS ET SUPPRIMÉS"
echo "  NetBird          : déconnecté et désactivé"
if [ "$PURGE_DATA" -eq 1 ]; then
  echo "  Données /data    : ⚠️  DÉTRUITES (--purge-data) — IRRÉVERSIBLE"
else
  echo "  Données /data    : ✅ CONSERVÉES (photos, fichiers, configs)"
fi
if [ "$PURGE_DOCKER" -eq 1 ]; then
  echo "  Paquets Docker   : SUPPRIMÉS (--purge-docker)"
else
  echo "  Paquets Docker   : conservés"
fi
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ "$PURGE_DATA" -eq 1 ]; then
    read -p "⚠️  TOUTES LES DONNÉES de /data seront PERDUES. Tapez 'DETRUIRE' pour confirmer : " CONFIRM
    [ "$CONFIRM" = "DETRUIRE" ] || { echo "Abandon."; exit 1; }
  else
    read -p "Confirmer la désinstallation de Ryvie ? (oui/non) : " CONFIRM
    [ "$CONFIRM" = "oui" ] || { echo "Abandon."; exit 1; }
  fi
fi

echo ""
echo "----------------------------------------------------"
echo "1/7 Arrêt des services PM2"
echo "----------------------------------------------------"
if command -v pm2 >/dev/null 2>&1; then
  sudo -u "$EXEC_USER" pm2 delete all 2>/dev/null || true
  sudo -u "$EXEC_USER" pm2 save --force 2>/dev/null || true
  # Retirer le démarrage automatique PM2 (service systemd pm2-<user>)
  sudo pm2 unstartup systemd -u "$EXEC_USER" --hp "$(getent passwd "$EXEC_USER" | cut -d: -f6)" 2>/dev/null || true
  sudo systemctl disable "pm2-$EXEC_USER" 2>/dev/null || true
  echo "✅ Services PM2 supprimés."
else
  echo "ℹ️ PM2 non installé, rien à faire."
fi

echo ""
echo "----------------------------------------------------"
echo "2/7 Arrêt et suppression des conteneurs Docker"
echo "----------------------------------------------------"
if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
  # Descendre proprement les stacks compose connues (apps + ldap)
  for compose in "$DATA_ROOT"/apps/*/docker-compose.yml \
                 "$DATA_ROOT"/apps/*/*/docker-compose.yml \
                 "$DATA_ROOT"/config/ldap/docker-compose.yml; do
    [ -f "$compose" ] || continue
    echo "  ↓ docker compose down : $(dirname "$compose")"
    sudo docker compose -f "$compose" down --remove-orphans 2>/dev/null || true
  done
  # Puis tout conteneur restant (keycloak, caddy, etc.)
  REMAINING=$(sudo docker ps -aq)
  if [ -n "$REMAINING" ]; then
    sudo docker stop $REMAINING 2>/dev/null || true
    sudo docker rm -f $REMAINING 2>/dev/null || true
  fi
  echo "✅ Conteneurs arrêtés et supprimés."
  if [ "$PURGE_DATA" -eq 1 ]; then
    # Les volumes/images ne servent plus à rien si on détruit /data
    sudo docker system prune -af --volumes 2>/dev/null || true
    echo "✅ Images et volumes Docker purgés."
  fi
else
  echo "ℹ️ Docker non disponible, rien à faire."
fi

echo ""
echo "----------------------------------------------------"
echo "3/7 NetBird"
echo "----------------------------------------------------"
if command -v netbird >/dev/null 2>&1; then
  sudo netbird down 2>/dev/null || true
  sudo systemctl disable --now netbird 2>/dev/null || true
  # Retirer le lien /var/lib/netbird → /data/netbird
  [ -L /var/lib/netbird ] && sudo rm -f /var/lib/netbird
  echo "✅ NetBird déconnecté et désactivé (paquet conservé, identité dans $DATA_ROOT/netbird)."
else
  echo "ℹ️ NetBird non installé."
fi

echo ""
echo "----------------------------------------------------"
echo "4/7 Suppression du code applicatif"
echo "----------------------------------------------------"
if [ -d "$RYVIE_DIR" ]; then
  sudo rm -rf "$RYVIE_DIR"
  echo "✅ $RYVIE_DIR supprimé."
else
  echo "ℹ️ $RYVIE_DIR absent."
fi
# Service d'installation automatique éventuel
sudo systemctl disable ryvie-install.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ryvie-install.service /root/run-install.sh

echo ""
echo "----------------------------------------------------"
echo "5/7 Hostname avahi"
echo "----------------------------------------------------"
if [ -f /etc/avahi/avahi-daemon.conf ] && grep -q '^host-name=ryvie' /etc/avahi/avahi-daemon.conf; then
  sudo sed -i 's/^host-name=ryvie/#host-name=/' /etc/avahi/avahi-daemon.conf
  sudo systemctl restart avahi-daemon 2>/dev/null || true
  echo "✅ Hostname mDNS 'ryvie.local' retiré."
else
  echo "ℹ️ Rien à faire."
fi

echo ""
echo "----------------------------------------------------"
echo "6/7 Données /data"
echo "----------------------------------------------------"
if [ "$PURGE_DATA" -eq 1 ]; then
  # Docker/containerd pointent sur /data → on doit les arrêter et les repointer sur /var/lib
  sudo systemctl stop docker containerd 2>/dev/null || true
  if [ -f /etc/docker/daemon.json ] && command -v jq >/dev/null 2>&1; then
    sudo sh -c 'jq "del(.\"data-root\")" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json' || true
  fi
  [ -f /etc/containerd/config.toml ] && sudo sed -i '/^root = "\/data\/containerd"/d' /etc/containerd/config.toml

  if findmnt -no TARGET "$DATA_ROOT" >/dev/null 2>&1; then
    sudo umount -l "$DATA_ROOT" 2>/dev/null || true
  fi
  # Retirer l'entrée fstab de /data (partition ou image loopback)
  sudo sed -i "\|[[:space:]]${DATA_ROOT}[[:space:]]|d" /etc/fstab
  # Supprimer l'image loopback si elle existe
  if [ -f "$DATA_IMG" ]; then
    sudo rm -f "$DATA_IMG"
    echo "✅ Image loopback $DATA_IMG supprimée."
  fi
  # Vider le point de montage résiduel
  sudo rm -rf "${DATA_ROOT:?}" 2>/dev/null || true
  echo "✅ /data détruit."
  echo "ℹ️ Si /data était une partition/RAID dédié, le disque n'est PAS reformaté (démonté uniquement)."
  if [ "$PURGE_DOCKER" -ne 1 ]; then
    sudo systemctl start containerd docker 2>/dev/null || true
  fi
else
  echo "✅ /data conservé intégralement (photos, fichiers, annuaire, configs)."
  echo "   → Une réinstallation via install.sh retrouvera ces données."
fi

echo ""
echo "----------------------------------------------------"
echo "7/7 Paquets Docker"
echo "----------------------------------------------------"
if [ "$PURGE_DOCKER" -eq 1 ]; then
  sudo systemctl disable --now docker containerd 2>/dev/null || true
  sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
  echo "✅ Paquets Docker supprimés."
else
  echo "ℹ️ Paquets Docker conservés."
fi

echo ""
echo "====================================================="
echo "✅ Désinstallation de Ryvie terminée."
if [ "$PURGE_DATA" -ne 1 ]; then
  echo "   Vos données sont intactes dans $DATA_ROOT."
fi
echo "   Non supprimés volontairement : utilisateur '$EXEC_USER', sudoers,"
echo "   Node.js/npm/PM2, Redis, paquet NetBird."
echo "====================================================="
