#!/bin/bash

# =======================================================================
# Script de désinstallation complète Ryvie OS
# Par Jules Maisonnave
# =======================================================================

set -euo pipefail

# Variables globales
UNINSTALL_LOG="/tmp/ryvie_uninstall_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/ryvie_uninstall_backup_$(date +%Y%m%d_%H%M%S)"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$UNINSTALL_LOG"
}

# Fonction d'erreur
error_exit() {
    local line_number=$1
    local error_code=$2
    log "❌ ERREUR: Ligne $line_number, Code d'erreur: $error_code"
    log "🔍 Consultez le log: $UNINSTALL_LOG"
    exit $error_code
}

# Piège pour capturer les erreurs (non-fatal pour la désinstallation)
trap 'log "⚠️ Erreur ligne ${LINENO}, mais on continue..." || true' ERR

# Fonction de sauvegarde de fichier
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        cp "$file" "$BACKUP_DIR/$file" 2>/dev/null || true
        log "💾 Sauvegardé: $file"
    fi
}

# Fonction pour demander confirmation
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "$FORCE_UNINSTALL" == "true" ]]; then
        log "🤖 Mode forcé activé: $message -> OUI"
        return 0
    fi
    
    echo ""
    read -p "$message (O/N) [défaut: $default]: " choice
    choice=${choice:-$default}
    
    if [[ "$choice" =~ ^[Oo]$ ]]; then
        log "✅ Confirmé: $message"
        return 0
    else
        log "⏭️ Ignoré: $message"
        return 1
    fi
}

# Fonction pour arrêter et supprimer les conteneurs Docker
remove_docker_containers() {
    log "🐳 Recherche et suppression des conteneurs Ryvie..."
    
    # Liste des conteneurs Ryvie connus
    local containers=(
        "openldap"
        "immich"
        "immich-server"
        "immich-web"
        "immich-machine-learning"
        "immich-microservices"
        "immich-postgres"
        "immich-redis"
        "postgres"
        "redis"
        "rTransfer"
        "snapdrop"
        "ryvie-backend"
    )
    
    # Arrêter tous les conteneurs en cours
    local running_containers=$(docker ps -q 2>/dev/null || true)
    if [[ -n "$running_containers" ]]; then
        log "🛑 Arrêt de tous les conteneurs en cours..."
        docker stop $running_containers 2>/dev/null || true
    fi
    
    # Supprimer les conteneurs spécifiques
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            log "🗑️ Suppression du conteneur: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Supprimer tous les conteneurs arrêtés
    local stopped_containers=$(docker ps -aq 2>/dev/null || true)
    if [[ -n "$stopped_containers" ]]; then
        if confirm_action "Supprimer TOUS les conteneurs Docker arrêtés"; then
            docker rm $stopped_containers 2>/dev/null || true
            log "🧹 Tous les conteneurs arrêtés supprimés"
        fi
    fi
}

# Fonction pour supprimer les images Docker
remove_docker_images() {
    log "🖼️ Suppression des images Docker Ryvie..."
    
    # Liste des images Ryvie connues
    local images=(
        "bitnami/openldap"
        "ghcr.io/immich-app/immich-server"
        "ghcr.io/immich-app/immich-web"
        "ghcr.io/immich-app/immich-machine-learning"
        "postgres"
        "redis"
        "linuxserver/snapdrop"
    )
    
    for image in "${images[@]}"; do
        local image_ids=$(docker images --format "{{.ID}}" --filter "reference=${image}*" 2>/dev/null || true)
        if [[ -n "$image_ids" ]]; then
            log "🗑️ Suppression de l'image: $image"
            docker rmi -f $image_ids 2>/dev/null || true
        fi
    done
    
    # Nettoyer les images orphelines
    if confirm_action "Supprimer les images Docker orphelines (dangling)"; then
        docker image prune -f 2>/dev/null || true
        log "🧹 Images orphelines supprimées"
    fi
    
    # Nettoyer toutes les images inutilisées
    if confirm_action "Supprimer TOUTES les images Docker inutilisées"; then
        docker image prune -a -f 2>/dev/null || true
        log "🧹 Toutes les images inutilisées supprimées"
    fi
}

# Fonction pour supprimer les volumes Docker
remove_docker_volumes() {
    log "💾 Suppression des volumes Docker..."
    
    # Supprimer les volumes spécifiques
    local volumes=(
        "openldap_data"
        "immich_pgdata"
        "immich_upload"
        "postgres_data"
        "redis_data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -q "^${volume}$"; then
            log "🗑️ Suppression du volume: $volume"
            docker volume rm "$volume" 2>/dev/null || true
        fi
    done
    
    # Nettoyer tous les volumes inutilisés
    if confirm_action "Supprimer TOUS les volumes Docker inutilisés"; then
        docker volume prune -f 2>/dev/null || true
        log "🧹 Volumes inutilisés supprimés"
    fi
}

# Fonction pour supprimer les réseaux Docker
remove_docker_networks() {
    log "🌐 Suppression des réseaux Docker personnalisés..."
    
    local networks=(
        "my_custom_network"
        "ryvie_network"
        "immich_network"
    )
    
    for network in "${networks[@]}"; do
        if docker network ls --format "{{.Name}}" 2>/dev/null | grep -q "^${network}$"; then
            log "🗑️ Suppression du réseau: $network"
            docker network rm "$network" 2>/dev/null || true
        fi
    done
    
    # Nettoyer les réseaux inutilisés
    docker network prune -f 2>/dev/null || true
    log "🧹 Réseaux Docker nettoyés"
}

# Fonction pour supprimer les dossiers de projet
remove_project_directories() {
    log "📁 Suppression des dossiers de projet Ryvie..."
    
    # Déterminer les dossiers de travail possibles
    local workdirs=(
        "$HOME/Bureau"
        "$HOME/Desktop" 
        "$HOME"
    )
    
    local projects=(
        "Ryvie-rPictures"
        "Ryvie-rTransfer"
        "Ryvie-rdrop"
        "Ryvie"
        "ldap"
    )
    
    for workdir in "${workdirs[@]}"; do
        if [[ -d "$workdir" ]]; then
            for project in "${projects[@]}"; do
                local project_path="$workdir/$project"
                if [[ -d "$project_path" ]]; then
                    if confirm_action "Supprimer le dossier: $project_path"; then
                        # Sauvegarder les fichiers de configuration importants
                        if [[ -f "$project_path/.env" ]]; then
                            backup_file "$project_path/.env"
                        fi
                        if [[ -f "$project_path/config.yaml" ]]; then
                            backup_file "$project_path/config.yaml"
                        fi
                        
                        rm -rf "$project_path" 2>/dev/null || true
                        log "🗑️ Supprimé: $project_path"
                    fi
                fi
            done
        fi
    done
}

# Fonction pour désinstaller les paquets
remove_packages() {
    log "📦 Désinstallation des paquets installés par Ryvie..."
    
    local packages=(
        "docker-ce"
        "docker-ce-cli" 
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
        "avahi-daemon"
        "avahi-utils"
        "ldap-utils"
        "npm"
    )
    
    if confirm_action "Désinstaller Docker et ses composants"; then
        for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
            if dpkg -l 2>/dev/null | grep -q "^ii.*$package "; then
                log "🗑️ Désinstallation: $package"
                sudo apt remove -y "$package" 2>/dev/null || true
            fi
        done
        
        # Supprimer le dépôt Docker
        sudo rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        sudo rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        log "🧹 Dépôt Docker supprimé"
    fi
    
    if confirm_action "Désinstaller les outils LDAP et Avahi"; then
        for package in avahi-daemon avahi-utils ldap-utils; do
            if dpkg -l 2>/dev/null | grep -q "^ii.*$package "; then
                log "🗑️ Désinstallation: $package"
                sudo apt remove -y "$package" 2>/dev/null || true
            fi
        done
    fi
    
    if confirm_action "Désinstaller npm (ATTENTION: peut affecter d'autres projets)"; then
        if dpkg -l 2>/dev/null | grep -q "^ii.*npm "; then
            log "🗑️ Désinstallation: npm"
            sudo apt remove -y npm 2>/dev/null || true
        fi
    fi
    
    # Nettoyer les paquets orphelins
    if confirm_action "Nettoyer les paquets orphelins"; then
        sudo apt autoremove -y 2>/dev/null || true
        sudo apt autoclean 2>/dev/null || true
        log "🧹 Paquets orphelins nettoyés"
    fi
}

# Fonction pour restaurer les fichiers de configuration
restore_config_files() {
    log "⚙️ Restauration des fichiers de configuration..."
    
    # Restaurer avahi-daemon.conf
    if [[ -f "/etc/avahi/avahi-daemon.conf" ]]; then
        backup_file "/etc/avahi/avahi-daemon.conf"
        if confirm_action "Restaurer la configuration Avahi par défaut"; then
            sudo sed -i 's/^host-name=ryvie/#host-name=/' /etc/avahi/avahi-daemon.conf 2>/dev/null || true
            sudo systemctl restart avahi-daemon 2>/dev/null || true
            log "✅ Configuration Avahi restaurée"
        fi
    fi
}

# Fonction pour retirer l'utilisateur du groupe docker
remove_user_from_docker_group() {
    log "👤 Gestion du groupe Docker..."
    
    if id -nG "$USER" | grep -qw "docker"; then
        if confirm_action "Retirer l'utilisateur $USER du groupe docker"; then
            sudo deluser "$USER" docker 2>/dev/null || true
            log "✅ Utilisateur $USER retiré du groupe docker"
            log "⚠️ Vous devez vous reconnecter pour appliquer ce changement"
        fi
    else
        log "ℹ️ L'utilisateur $USER n'est pas dans le groupe docker"
    fi
}

# Fonction pour supprimer les processus en cours
stop_ryvie_processes() {
    log "⏹️ Arrêt des processus Ryvie..."
    
    # Chercher les processus Node.js liés à Ryvie
    local node_processes=$(pgrep -f "node.*index.js" 2>/dev/null || true)
    if [[ -n "$node_processes" ]]; then
        if confirm_action "Arrêter les processus Node.js Ryvie"; then
            echo "$node_processes" | xargs kill 2>/dev/null || true
            log "🛑 Processus Node.js arrêtés"
        fi
    fi
    
    # Arrêter NetBird VPN s'il est installé
    if command -v netbird &> /dev/null; then
        if confirm_action "Arrêter et désinstaller NetBird VPN"; then
            netbird down 2>/dev/null || true
            sudo apt remove -y netbird 2>/dev/null || true
            log "🛑 NetBird VPN supprimé"
        fi
    fi
}

# Fonction pour nettoyer les modules Node.js globaux
cleanup_nodejs() {
    log "🟢 Nettoyage des modules Node.js..."
    
    if command -v npm &> /dev/null; then
        if confirm_action "Désinstaller les modules Node.js globaux installés par Ryvie"; then
            # Désinstaller 'n' (Node version manager)
            sudo npm uninstall -g n 2>/dev/null || true
            log "🗑️ Module 'n' désinstallé"
        fi
        
        # Nettoyer le cache npm
        if confirm_action "Nettoyer le cache npm"; then
            npm cache clean --force 2>/dev/null || true
            log "🧹 Cache npm nettoyé"
        fi
    fi
}

# Fonction principale de désinstallation
main_uninstall() {
    log "🚀 Début de la désinstallation complète de Ryvie OS"
    
    # Créer le dossier de sauvegarde
    mkdir -p "$BACKUP_DIR"
    
    # 1. Arrêter les processus
    stop_ryvie_processes
    
    # 2. Docker - Conteneurs
    if command -v docker &> /dev/null; then
        remove_docker_containers
        remove_docker_images
        remove_docker_volumes  
        remove_docker_networks
    else
        log "ℹ️ Docker n'est pas installé, étapes Docker ignorées"
    fi
    
    # 3. Dossiers de projet
    remove_project_directories
    
    # 4. Fichiers de configuration
    restore_config_files
    
    # 5. Utilisateur et groupes
    remove_user_from_docker_group
    
    # 6. Modules Node.js
    cleanup_nodejs
    
    # 7. Paquets système
    remove_packages
    
    log "✅ Désinstallation terminée"
    
    # Résumé final
    echo ""
    echo "🎯 DÉSINSTALLATION RYVIE OS TERMINÉE"
    echo "==========================================="
    echo "📋 Résumé des actions effectuées:"
    echo "   • Conteneurs Docker supprimés"
    echo "   • Images Docker nettoyées" 
    echo "   • Volumes et réseaux Docker supprimés"
    echo "   • Dossiers de projet supprimés"
    echo "   • Configuration système restaurée"
    echo "   • Processus arrêtés"
    echo ""
    echo "📁 Log de désinstallation: $UNINSTALL_LOG"
    echo "💾 Sauvegardes disponibles: $BACKUP_DIR"
    echo ""
    echo "⚠️  ACTIONS MANUELLES REQUISES:"
    echo "   • Redémarrez votre session si vous avez quitté le groupe docker"
    echo "   • Vérifiez manuellement s'il reste des fichiers dans /opt ou /usr/local"
    echo ""
}

# =====================================================
# DÉBUT DU SCRIPT
# =====================================================

echo ""
echo "
 ❌ _____             _         ____   _____ 
   |  __ \           (_)       / __ \ / ____|
   | |__) |   ___   ___  ___  | |  | | (___  
   |  _  / | | \ \ / / |/ _ \ | |  | |\___ \ 
   | | \ \ |_| |\ V /| |  __/ | |__| |____) |
   |_|  \_\__, | \_/ |_|\___|  \____/|_____/ 
           __/ |                             
          |___/                              
"
echo ""
echo "🗑️ DÉSINSTALLATION COMPLÈTE DE RYVIE OS"
echo "Par Jules Maisonnave"
echo ""

# Vérifier les arguments
FORCE_UNINSTALL="false"
SKIP_CONFIRMATION="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE_UNINSTALL="true"
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force, -f     Désinstallation forcée sans confirmation"
            echo "  --yes, -y       Répondre 'oui' à toutes les questions"
            echo "  --help, -h      Afficher cette aide"
            echo ""
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilisez --help pour voir les options disponibles"
            exit 1
            ;;
    esac
done

# Confirmation finale
if [[ "$FORCE_UNINSTALL" != "true" ]] && [[ "$SKIP_CONFIRMATION" != "true" ]]; then
    echo "⚠️  ATTENTION: Cette opération va supprimer complètement Ryvie OS"
    echo "   • Tous les conteneurs Docker Ryvie"
    echo "   • Toutes les données et configurations"  
    echo "   • Les dossiers de projet"
    echo "   • Les paquets installés"
    echo ""
    echo "💾 Des sauvegardes seront créées dans: $BACKUP_DIR"
    echo ""
    read -p "Êtes-vous ABSOLUMENT sûr de vouloir continuer ? (oui/NON): " final_confirm
    
    if [[ "$final_confirm" != "oui" ]]; then
        echo "❌ Désinstallation annulée"
        exit 0
    fi
fi

# Lancer la désinstallation
main_uninstall

echo ""
echo "🏁 Désinstallation terminée. Au revoir ! 👋"
