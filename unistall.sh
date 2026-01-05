#!/usr/bin/env bash
# Ryvie OS Uninstall Script
# Désinstalle complètement tous les composants de Ryvie OS
# Version: 1.0.0

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${RED}"
echo "  _____             _         ____   _____ "
echo " |  __ \           (_)       / __ \ / ____|"
echo " | |__) |   ___   ___  ___  | |  | | (___  "
echo " |  _  / | | \ \ / / |/ _ \ | |  | |\___ \ "
echo " | | \ \ |_| |\ V /| |  __/ | |__| |____) |"
echo " |_|  \_\__, | \_/ |_|\___|  \____/|_____/ "
echo "         __/ |                             "
echo "        |___/                              "
echo -e "${NC}"
echo ""
echo -e "${RED}⚠️  DÉSINSTALLATION DE RYVIE OS ⚠️${NC}"
echo "By Jules Maisonnave"
echo "v0.0.1"
echo ""

# Détecter l'utilisateur réel
EXEC_USER="${SUDO_USER:-$USER}"
EXEC_HOME="$(getent passwd "$EXEC_USER" | cut -d: -f6)"
if [ -z "$EXEC_HOME" ]; then
    EXEC_HOME="/home/$EXEC_USER"
fi

# Chemins globaux (identiques à install.sh)
DATA_ROOT="/data"
APPS_DIR="$DATA_ROOT/apps"
CONFIG_DIR="$DATA_ROOT/config"
LOG_DIR="$DATA_ROOT/logs"
DOCKER_ROOT="$DATA_ROOT/docker"
RYVIE_ROOT="/opt"
IMAGES_DIR="$DATA_ROOT/images"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Confirmation de l'utilisateur
echo -e "${YELLOW}Cette opération va supprimer :${NC}"
echo "  - Tous les conteneurs Docker Ryvie"
echo "  - Tous les volumes Docker (données incluses)"
echo "  - Les applications dans $APPS_DIR"
echo "  - Les configurations dans $CONFIG_DIR"
echo "  - Le backend/frontend dans $RYVIE_ROOT/Ryvie"
echo "  - Les services PM2"
echo "  - NetBird et sa configuration"
echo "  - OpenLDAP et ses données"
echo "  - Portainer"
echo ""
echo -e "${RED}⚠️  CETTE ACTION EST IRRÉVERSIBLE !${NC}"
echo -e "${YELLOW}Les données dans /data seront SUPPRIMÉES définitivement.${NC}"
echo ""
read -p "Êtes-vous sûr de vouloir continuer ? (tapez 'YES' en majuscules pour confirmer) : " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Désinstallation annulée."
    exit 0
fi

echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}Début de la désinstallation...${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

# =====================================================
# Étape 1: Arrêt et suppression des services PM2
# =====================================================
echo "-----------------------------------------------------"
echo "Étape 1: Arrêt des services PM2"
echo "-----------------------------------------------------"

if command -v pm2 &> /dev/null; then
    log_info "Arrêt de tous les processus PM2..."
    sudo -u "$EXEC_USER" pm2 stop all 2>/dev/null || true
    sudo -u "$EXEC_USER" pm2 delete all 2>/dev/null || true
    sudo -u "$EXEC_USER" pm2 save --force 2>/dev/null || true
    
    log_info "Suppression du démarrage automatique PM2..."
    sudo pm2 unstartup systemd -u "$EXEC_USER" --hp "$EXEC_HOME" 2>/dev/null || true
    
    log_info "Nettoyage des fichiers PM2..."
    sudo -u "$EXEC_USER" rm -rf "$EXEC_HOME/.pm2" 2>/dev/null || true
    
    log_info "✅ Services PM2 arrêtés et supprimés"
else
    log_warning "PM2 non installé, skip"
fi

# =====================================================
# Étape 2: Arrêt et suppression des conteneurs Docker
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 2: Arrêt et suppression des conteneurs Docker"
echo "-----------------------------------------------------"

if command -v docker &> /dev/null; then
    # Arrêter et supprimer rDrive
    if [ -d "$APPS_DIR/Ryvie-rDrive/tdrive" ]; then
        log_info "Arrêt de rDrive..."
        cd "$APPS_DIR/Ryvie-rDrive/tdrive"
        sudo docker compose down -v 2>/dev/null || true
    fi
    
    # Arrêter et supprimer rDrop
    if [ -d "$APPS_DIR/Ryvie-rdrop/rDrop-main" ]; then
        log_info "Arrêt de rDrop..."
        cd "$APPS_DIR/Ryvie-rdrop/rDrop-main"
        sudo docker compose down -v --remove-orphans 2>/dev/null || true
    fi
    
    # Arrêter et supprimer rTransfer
    if [ -d "$APPS_DIR/Ryvie-rTransfer" ]; then
        log_info "Arrêt de rTransfer..."
        cd "$APPS_DIR/Ryvie-rTransfer"
        sudo docker compose down -v 2>/dev/null || true
    fi
    
    # Arrêter et supprimer rPictures
    if [ -d "$APPS_DIR/Ryvie-rPictures/docker" ]; then
        log_info "Arrêt de rPictures..."
        cd "$APPS_DIR/Ryvie-rPictures/docker"
        sudo docker compose down -v 2>/dev/null || true
    fi
    
    # Arrêter et supprimer OpenLDAP
    if [ -d "$CONFIG_DIR/ldap" ]; then
        log_info "Arrêt d'OpenLDAP..."
        cd "$CONFIG_DIR/ldap"
        sudo docker compose down -v 2>/dev/null || true
    fi
    
    # Supprimer Portainer
    log_info "Suppression de Portainer..."
    sudo docker stop portainer 2>/dev/null || true
    sudo docker rm portainer 2>/dev/null || true
    
    # Nettoyage des conteneurs orphelins
    log_info "Nettoyage des conteneurs orphelins..."
    sudo docker container prune -f 2>/dev/null || true
    
    # Suppression de tous les volumes Docker Ryvie
    log_info "Suppression des volumes Docker..."
    sudo docker volume ls -q | grep -E "(ryvie|rdrive|rdrop|rtransfer|rpictures|immich|openldap|portainer)" | xargs -r sudo docker volume rm -f 2>/dev/null || true
    
    # Nettoyage des volumes orphelins
    sudo docker volume prune -f 2>/dev/null || true
    
    # Nettoyage des réseaux
    log_info "Nettoyage des réseaux Docker..."
    sudo docker network prune -f 2>/dev/null || true
    
    # Suppression des images Docker Ryvie
    log_info "Suppression des images Docker..."
    sudo docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(ryvie|rdrive|rdrop|rtransfer|rpictures|immich|openldap|portainer|julescloud)" | xargs -r sudo docker rmi -f 2>/dev/null || true
    
    # Suppression de l'image hello-world (test Docker)
    sudo docker rmi hello-world 2>/dev/null || true
    
    # Nettoyage des images orphelines (dangling)
    log_info "Nettoyage des images orphelines..."
    sudo docker image prune -af 2>/dev/null || true
    
    log_info "✅ Conteneurs, volumes, réseaux et images Docker supprimés"
else
    log_warning "Docker non installé, skip"
fi

# =====================================================
# Étape 3: Arrêt et désinstallation de NetBird
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 3: Désinstallation de NetBird"
echo "-----------------------------------------------------"

# Vérifier si NetBird est installé (commande OU paquet APT)
if command -v netbird &> /dev/null || dpkg -l | grep -q netbird; then
    log_info "Déconnexion de NetBird..."
    sudo netbird down 2>/dev/null || true
    
    log_info "Arrêt du service NetBird..."
    sudo systemctl stop netbird 2>/dev/null || true
    sudo systemctl disable netbird 2>/dev/null || true
    
    log_info "Désinstallation du paquet NetBird via APT..."
    # Désinstaller le paquet APT (méthode d'installation officielle)
    sudo apt remove --purge -y netbird 2>/dev/null || true
    sudo apt autoremove -y 2>/dev/null || true
    
    log_info "Suppression des binaires NetBird..."
    # Supprimer tous les binaires possibles
    sudo rm -f /usr/bin/netbird 2>/dev/null || true
    sudo rm -f /usr/local/bin/netbird 2>/dev/null || true
    sudo rm -f /opt/netbird/netbird 2>/dev/null || true
    
    # Suppression du service systemd
    sudo rm -f /etc/systemd/system/netbird.service 2>/dev/null || true
    sudo rm -f /lib/systemd/system/netbird.service 2>/dev/null || true
    sudo systemctl daemon-reload
    
    # Suppression du symlink /var/lib/netbird (créé par install.sh)
    if [ -L /var/lib/netbird ]; then
        log_info "Suppression du symlink /var/lib/netbird..."
        sudo rm -f /var/lib/netbird
    elif [ -d /var/lib/netbird ]; then
        # Si c'est un répertoire réel (ancienne installation)
        sudo rm -rf /var/lib/netbird
    fi
    
    # Restaurer l'ancien backup si présent (nettoyage)
    sudo rm -rf /var/lib/netbird.bak.* 2>/dev/null || true
    
    # Suppression des données NetBird dans /data
    if [ -d "$DATA_ROOT/netbird" ]; then
        log_info "Suppression des données NetBird dans $DATA_ROOT/netbird..."
        # Si c'est un sous-volume Btrfs, le supprimer proprement
        if command -v btrfs &> /dev/null && sudo btrfs subvolume show "$DATA_ROOT/netbird" &>/dev/null; then
            sudo btrfs subvolume delete "$DATA_ROOT/netbird" 2>/dev/null || sudo rm -rf "$DATA_ROOT/netbird"
        else
            sudo rm -rf "$DATA_ROOT/netbird"
        fi
    fi
    
    # Suppression de la configuration NetBird
    sudo rm -rf /etc/netbird 2>/dev/null || true
    
    # Suppression du dépôt APT et des clés
    log_info "Suppression du dépôt APT NetBird..."
    sudo rm -f /etc/apt/sources.list.d/netbird.list 2>/dev/null || true
    sudo rm -f /usr/share/keyrings/netbird-archive-keyring.gpg 2>/dev/null || true
    
    # Nettoyage du cache APT
    sudo apt update -qq 2>/dev/null || true
    
    log_info "✅ NetBird complètement désinstallé"
else
    log_warning "NetBird non installé, skip"
fi

# =====================================================
# Étape 4: Arrêt des services système
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 4: Arrêt des services système"
echo "-----------------------------------------------------"

# Arrêt de Redis
if systemctl is-active --quiet redis-server 2>/dev/null; then
    log_info "Arrêt de Redis..."
    sudo systemctl stop redis-server 2>/dev/null || true
    sudo systemctl disable redis-server 2>/dev/null || true
fi

# Arrêt d'Avahi
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    log_info "Arrêt d'Avahi..."
    sudo systemctl stop avahi-daemon 2>/dev/null || true
    sudo systemctl disable avahi-daemon 2>/dev/null || true
    sudo rm -f /etc/avahi/avahi-daemon.conf.bak 2>/dev/null || true
fi

log_info "✅ Services système arrêtés"

# =====================================================
# Étape 5: Suppression des répertoires d'applications
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 5: Suppression des applications"
echo "-----------------------------------------------------"

# Suppression du backend/frontend principal
if [ -d "$RYVIE_ROOT/Ryvie" ]; then
    log_info "Suppression de $RYVIE_ROOT/Ryvie..."
    sudo rm -rf "$RYVIE_ROOT/Ryvie"
fi

# Suppression des applications dans /data/apps
if [ -d "$APPS_DIR" ]; then
    log_info "Suppression de $APPS_DIR..."
    sudo rm -rf "$APPS_DIR/Ryvie-rPictures" 2>/dev/null || true
    sudo rm -rf "$APPS_DIR/Ryvie-rTransfer" 2>/dev/null || true
    sudo rm -rf "$APPS_DIR/Ryvie-rdrop" 2>/dev/null || true
    sudo rm -rf "$APPS_DIR/Ryvie-rDrive" 2>/dev/null || true
fi

log_info "✅ Applications supprimées"

# =====================================================
# Étape 6: Suppression des configurations
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 6: Suppression des configurations"
echo "-----------------------------------------------------"

if [ -d "$CONFIG_DIR" ]; then
    log_info "Suppression des configurations..."
    sudo rm -rf "$CONFIG_DIR/ldap" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/netbird" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/rdrive" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/rtransfer" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/rdrop" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/backend-view" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/rclone" 2>/dev/null || true
    sudo rm -rf "$CONFIG_DIR/user-preferences" 2>/dev/null || true
fi

log_info "✅ Configurations supprimées"

# =====================================================
# Étape 7: Suppression des logs
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 7: Suppression des logs"
echo "-----------------------------------------------------"

if [ -d "$LOG_DIR" ]; then
    log_info "Suppression des logs..."
    sudo rm -rf "$LOG_DIR"/*
fi

log_info "✅ Logs supprimés"

# =====================================================
# Étape 8: Suppression des images de fond
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 8: Suppression des images"
echo "-----------------------------------------------------"

if [ -d "$IMAGES_DIR" ]; then
    log_info "Suppression des images..."
    sudo rm -rf "$IMAGES_DIR"/*
fi

log_info "✅ Images supprimées"

# =====================================================
# Étape 9: Suppression des fichiers de configuration système
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 9: Nettoyage des fichiers système"
echo "-----------------------------------------------------"

log_info "Suppression des fichiers profile.d..."
sudo rm -f /etc/profile.d/ryvie_pm2.sh 2>/dev/null || true
sudo rm -f /etc/profile.d/ryvie_rclone.sh 2>/dev/null || true

log_info "✅ Fichiers système nettoyés"

# =====================================================
# Étape 10: Suppression des sous-volumes Btrfs et nettoyage complet de /data
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 10: Suppression des sous-volumes Btrfs et nettoyage de /data"
echo "-----------------------------------------------------"

if command -v btrfs &> /dev/null && [ -d "$DATA_ROOT" ]; then
    if [[ "$(findmnt -no FSTYPE "$DATA_ROOT")" == "btrfs" ]]; then
        log_info "Suppression des sous-volumes Btrfs..."
        
        # Liste des sous-volumes à supprimer (netbird déjà supprimé à l'étape 3)
        for subvol in "$APPS_DIR" "$CONFIG_DIR" "$DOCKER_ROOT" "$LOG_DIR" "$IMAGES_DIR" "$DATA_ROOT/snapshot" "$DATA_ROOT/containerd"; do
            if [ -d "$subvol" ] && sudo btrfs subvolume show "$subvol" &>/dev/null; then
                log_info "Suppression du sous-volume: $subvol"
                sudo btrfs subvolume delete "$subvol" 2>/dev/null || true
            fi
        done
        
        log_info "✅ Sous-volumes Btrfs supprimés"
    else
        log_warning "/data n'est pas en Btrfs, skip de la suppression des sous-volumes"
    fi
fi

# Suppression des répertoires restants dans /data (non sous-volumes ou répertoires résiduels)
log_info "Nettoyage des répertoires restants dans /data..."

# Portainer (données Docker non gérées par compose)
if [ -d "$DATA_ROOT/portainer" ]; then
    log_info "Suppression de $DATA_ROOT/portainer..."
    sudo rm -rf "$DATA_ROOT/portainer"
fi

# Containerd (si non sous-volume ou résiduel)
if [ -d "$DATA_ROOT/containerd" ]; then
    log_info "Suppression de $DATA_ROOT/containerd..."
    sudo rm -rf "$DATA_ROOT/containerd"
fi

# Snapshot (si non sous-volume ou résiduel)
if [ -d "$DATA_ROOT/snapshot" ]; then
    log_info "Suppression de $DATA_ROOT/snapshot..."
    sudo rm -rf "$DATA_ROOT/snapshot"
fi

# Docker root (volumes, overlay2, etc.)
if [ -d "$DOCKER_ROOT" ]; then
    log_info "Suppression de $DOCKER_ROOT..."
    sudo rm -rf "$DOCKER_ROOT"
fi

# Nettoyage de tous les autres répertoires dans /data
log_info "Suppression de tous les répertoires restants dans /data..."
for dir in "$DATA_ROOT"/*; do
    if [ -d "$dir" ]; then
        log_info "Suppression de $dir..."
        # Tenter de supprimer comme sous-volume Btrfs d'abord
        if command -v btrfs &> /dev/null && sudo btrfs subvolume show "$dir" &>/dev/null; then
            sudo btrfs subvolume delete "$dir" 2>/dev/null || sudo rm -rf "$dir"
        else
            sudo rm -rf "$dir"
        fi
    fi
done

log_info "✅ Répertoire /data complètement nettoyé"


# =====================================================
# Étape 12: Retrait de l'utilisateur du groupe docker
# =====================================================
echo ""
echo "-----------------------------------------------------"
echo "Étape 11: Nettoyage des groupes utilisateur"
echo "-----------------------------------------------------"

if getent group docker &> /dev/null; then
    if id -nG "$EXEC_USER" | grep -qw "docker"; then
        log_info "Retrait de $EXEC_USER du groupe docker..."
        sudo gpasswd -d "$EXEC_USER" docker 2>/dev/null || true
        log_info "✅ Utilisateur retiré du groupe docker"
    fi
fi

if id -nG ryvie &> /dev/null 2>&1; then
    if id -nG ryvie | grep -qw "sudo"; then
        log_info "Retrait de ryvie du groupe sudo..."
        sudo gpasswd -d ryvie sudo 2>/dev/null || true
    fi
fi

# =====================================================
# Étape 13: Informations finales
# =====================================================
echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}✅ Désinstallation de Ryvie OS terminée !${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""
echo -e "${YELLOW}Composants conservés (si installés) :${NC}"
echo "  - Docker Engine (non désinstallé)"
echo "  - Node.js et npm (non désinstallés)"
echo "  - PM2 global (non désinstallé)"
echo "  - Redis (service arrêté mais non désinstallé)"
echo "  - Paquets système (ldap-utils, avahi, etc.)"
echo ""
echo -e "${YELLOW}Pour désinstaller complètement ces composants :${NC}"
echo "  sudo apt remove --purge docker-ce docker-ce-cli containerd.io"
echo "  sudo apt remove --purge redis-server avahi-daemon"
echo "  sudo npm uninstall -g pm2"
echo "  sudo n rm <version>  # Pour supprimer Node.js"
echo ""
echo -e "${GREEN}Vous pouvez maintenant réinstaller Ryvie OS avec install.sh${NC}"
echo ""
