#!/usr/bin/env bash
# Détecter l’utilisateur réel même si le script est lancé avec sudo
EXEC_USER="${SUDO_USER:-$USER}"
EXEC_HOME="$(getent passwd "$EXEC_USER" | cut -d: -f6)"
if [ -z "$EXEC_HOME" ]; then
    EXEC_HOME="/home/$EXEC_USER"
fi

echo ""
echo "
  _____             _         ____   _____ 
 |  __ \           (_)       / __ \ / ____|
 | |__) |   ___   ___  ___  | |  | | (___  
 |  _  / | | \ \ / / |/ _ \ | |  | |\___ \ 
 | | \ \ |_| |\ V /| |  __/ | |__| |____) |
 |_|  \_\__, | \_/ |_|\___|  \____/|_____/ 
         __/ |                             
        |___/                              
"
echo ""
echo "Bienvenue sur Ryvie OS 🚀"
echo "By Jules Maisonnave"
echo "Ce script est un test : aucune installation n'est effectuée pour le moment."

# --- CHANGED: controlled strict mode for critical sections only ---
# Not failing globally; provide helpers to enable strict mode for critical parts
strict_enter() {
    # enable strict mode and a helpful ERR trap for the current shell
    set -euo pipefail
    set -o errtrace
    trap 'rc=$?; echo "❌ Erreur: la commande \"${BASH_COMMAND}\" a échoué avec le code $rc (fichier: ${BASH_SOURCE[0]}, ligne: $LINENO)"; exit $rc' ERR
}

strict_exit() {
    # disable strict mode and remove ERR trap (best-effort)
    trap - ERR || true
    set +e || true
    set +u || true
    set +o pipefail || true
    set +o errtrace || true
}

# --- CHANGED: safe defaults for variables that may be referenced while unset ---
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ID="${ID:-}"
VERSION_ID="${VERSION_ID:-}"

# =====================================================
# Global /data paths (strict OS/Data separation)
# =====================================================
DATA_ROOT="/data"
APPS_DIR="$DATA_ROOT/apps"
CONFIG_DIR="$DATA_ROOT/config"
LOG_DIR="$DATA_ROOT/logs"
DOCKER_ROOT="$DATA_ROOT/docker"
RYVIE_ROOT="/opt"
IMAGES_DIR="$DATA_ROOT/images"
USERPREF_DIR="$CONFIG_DIR/user-preferences"

sudo mkdir -p "$APPS_DIR" "$CONFIG_DIR" "$LOG_DIR" "$DOCKER_ROOT" "$RYVIE_ROOT" "$IMAGES_DIR/backgrounds" "$USERPREF_DIR" "$DATA_ROOT/snapshot"

# Permissions sécurisées : NE JAMAIS chown -R sur DOCKER_ROOT pour éviter de casser les volumes
# Seul le dossier racine /data (non récursif)
sudo chown "$EXEC_USER:$EXEC_USER" "$DATA_ROOT" || true
sudo chmod 755 "$DATA_ROOT" || true

# Donner la main à l'utilisateur sur les répertoires non système (SANS toucher à Docker)
sudo chown -R "$EXEC_USER:$EXEC_USER" "$APPS_DIR" "$CONFIG_DIR" "$LOG_DIR" "$IMAGES_DIR" || true
# Pour /opt, on attend que le dossier Ryvie soit créé pour ne pas chown tout /opt
# Les permissions seront appliquées après le clonage du repo

# Protection explicite : ne jamais modifier les permissions des volumes Docker
if [ -d "$DOCKER_ROOT" ]; then
  echo "ℹ️ Skip chown on $DOCKER_ROOT/* (volumes Docker protégés)"
fi

# PM2 utilise son répertoire par défaut (~/.pm2)
sudo rm -f /etc/profile.d/ryvie_pm2.sh

# rclone configuration path under /data/config
export RCLONE_CONFIG="$CONFIG_DIR/rclone/rclone.conf"
sudo mkdir -p "$(dirname "$RCLONE_CONFIG")"
sudo touch "$RCLONE_CONFIG" || true
sudo chmod 600 "$RCLONE_CONFIG" || true

# helper: retourne le répertoire de travail des apps (path-only)
get_work_dir() {
    printf '%s' "$APPS_DIR"
}

#vérification que /data est bien BTRFS
if [[ "$(findmnt -no FSTYPE "$DATA_ROOT")" != "btrfs" ]]; then
  echo "❌ $DATA_ROOT n'est pas en Btrfs — impossible de créer des sous-volumes."
  exit 1
fi

echo "----------------------------------------------------"
echo "Étape 0: Création des sous-volumes BTRFS"
echo "----------------------------------------------------"
# --- Convertir les répertoires clés en sous-volumes Btrfs (idempotent) ---
for dir in "$APPS_DIR" "$CONFIG_DIR" "$DOCKER_ROOT" "$LOG_DIR" "$IMAGES_DIR" "$DATA_ROOT/netbird"; do
  if [[ -d "$dir" ]]; then
    if ! sudo btrfs subvolume show "$dir" &>/dev/null; then
      echo "🧱 Création du sous-volume Btrfs : $dir"
      TMP="${dir}.tmp-$$"
      sudo mv "$dir" "$TMP"
      sudo btrfs subvolume create "$dir"
      sudo cp -a --reflink=always "$TMP"/. "$dir"/
      sudo rm -rf "$TMP"
    else
      echo "✅ $dir est déjà un sous-volume"
    fi
  fi
done

# Dossier snapshot isolé (ne sera jamais inclus dans les snapshots)
if [[ ! -d "$DATA_ROOT/snapshot" ]] || ! sudo btrfs subvolume show "$DATA_ROOT/snapshot" &>/dev/null; then
  sudo btrfs subvolume create "$DATA_ROOT/snapshot"
  echo "📦 Sous-volume snapshot créé : $DATA_ROOT/snapshot"
fi




# =====================================================
# Étape 1: Vérification des prérequis système
# =====================================================
echo "----------------------------------------------------"
echo "Étape 1: Vérification des prérequis système"
echo "----------------------------------------------------"

# 1. Vérification de l'architecture
ARCH=$(uname -m)
case "$ARCH" in
    *aarch64*)
        TARGET_ARCH="arm64"
        ;;
    *64*)
        TARGET_ARCH="amd64"
        ;;
    *armv7*)
        TARGET_ARCH="arm-7"
        ;;
    *)
        echo "Erreur: Architecture non supportée: $ARCH"
        exit 1
        ;;
esac
echo "Architecture détectée: $ARCH ($TARGET_ARCH)"

# 2. Vérification du système d'exploitation
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
    echo "Erreur: Ce script est conçu uniquement pour Linux. OS détecté: $OS"
    exit 1
fi
echo "Système d'exploitation: $OS"

# --- CHANGED: package manager abstraction + distro codename detection ---
# Détecter apt / apt-get et fournir une fonction d'installation non interactive
if command -v apt > /dev/null 2>&1; then
    APT_CMD="sudo apt"
else
    APT_CMD="sudo apt-get"
fi

install_pkgs() {
    export DEBIAN_FRONTEND=noninteractive
    # update quietly then install requested packages
    $APT_CMD update -qq || true
    $APT_CMD install -y "$@" || return 1
}

# Obtenir l'ID et VERSION_CODENAME depuis /etc/os-release pour choisir le dépôt Docker
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

# s'assurer d'avoir lsb_release si possible (pour la suite)
if ! command -v lsb_release > /dev/null 2>&1; then
    install_pkgs lsb-release || true
fi

if command -v lsb_release > /dev/null 2>&1; then
    DISTRO_CODENAME=$(lsb_release -cs)
else
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$DISTRO_CODENAME" ]; then
        # fallback mapping common versions (extend si besoin)
        case "${ID}${VERSION_ID}" in
            debian11) DISTRO_CODENAME="bullseye" ;;
            debian12) DISTRO_CODENAME="bookworm" ;;
            ubuntu20.04) DISTRO_CODENAME="focal" ;;
            ubuntu22.04) DISTRO_CODENAME="jammy" ;;
            *) DISTRO_CODENAME="stable" ;;
        esac
    fi
fi

# 2b. Installation de git et curl au début du script si absents
echo ""
echo "------------------------------------------"
echo " Vérification et installation de git et curl "
echo "------------------------------------------"

# Vérifier et installer git si nécessaire
if command -v git > /dev/null 2>&1; then
    echo "✅ git est déjà installé : $(git --version)"
else
    echo "⚙️ Installation de git..."
    install_pkgs git || { echo "❌ Échec de l'installation de git"; exit 1; }
fi

# Vérifier et installer curl si nécessaire
if command -v curl > /dev/null 2>&1; then
    echo "✅ curl est déjà installé : $(curl --version | head -n1)"
else
    echo "⚙️ Installation de curl..."
    install_pkgs curl || { echo "❌ Échec de l'installation de curl"; exit 1; }
fi

# Vérifier et installer jq si nécessaire (utilisé plus loin dans le script)
if command -v jq > /dev/null 2>&1; then
    echo "✅ jq est déjà installé : $(jq --version)"
else
    echo "⚙️ Installation de jq..."
    install_pkgs jq || { echo "❌ Échec de l'installation de jq"; exit 1; }
fi

# Vérifier et installer rsync si nécessaire (utilisé pour les migrations de données)
if command -v rsync > /dev/null 2>&1; then
    echo "✅ rsync est déjà installé : $(rsync --version | head -n1)"
else
    echo "⚙️ Installation de rsync..."
    install_pkgs rsync || { echo "❌ Échec de l'installation de rsync"; exit 1; }
fi

# 3. Vérification de la mémoire physique (minimum 400 MB)
MEMORY=$(free -m | awk '/Mem:/ {print $2}')
MIN_MEMORY=400
if [ "$MEMORY" -lt "$MIN_MEMORY" ]; then
    echo "Erreur: Mémoire insuffisante. ${MEMORY} MB détectés, minimum requis: ${MIN_MEMORY} MB."
    exit 1
fi
echo "Mémoire disponible: ${MEMORY} MB (OK)"

# 4. Vérification de l'espace disque libre sur la racine (minimum 5 GB)
FREE_DISK_KB=$(df -k / | tail -1 | awk '{print $4}')
FREE_DISK_GB=$(( FREE_DISK_KB / 1024 / 1024 ))
MIN_DISK_GB=5
if [ "$FREE_DISK_GB" -lt "$MIN_DISK_GB" ]; then
    echo "Erreur: Espace disque insuffisant. ${FREE_DISK_GB} GB détectés, minimum requis: ${MIN_DISK_GB} GB."
    exit 1
fi
echo "Espace disque libre: ${FREE_DISK_GB} GB (OK)"
echo ""
echo "------------------------------------------"
echo " Vérification et installation de npm "
echo "------------------------------------------"
echo ""

# Dépôts sur lesquels tu es invité
# Ryvie apps dans /data/apps
REPOS_APPS=(
    "Ryvie-rPictures"
    "Ryvie-rTransfer"
    "Ryvie-rdrop"
    "Ryvie-rDrive"
)
# Ryvie principal dans /opt/ryvie
REPOS_OPT=(
    "Ryvie"
)

# Branche à cloner: interroge si RYVIE_BRANCH n'est pas défini
if [ -z "${RYVIE_BRANCH:-}" ]; then
    read -p "Quelle branche veux-tu cloner ? [main]: " BRANCH_INPUT
    BRANCH="${BRANCH_INPUT:-main}"
else
    BRANCH="$RYVIE_BRANCH"
fi
echo "Branche sélectionnée: $BRANCH"

# Fonction de vérification des identifiants
verify_credentials() {
    local user="$1"
    local token="$2"
    local status_code

    status_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$token" https://api.github.com/user)
    [[ "$status_code" == "200" ]]
}

# Identifiants GitHub: interroge si non fournis via env
if [ -z "${GITHUB_USER:-}" ]; then
    read -p "Entrez votre nom d'utilisateur GitHub : " GITHUB_USER
fi
if [ -z "${GITHUB_TOKEN:-}" ]; then
    read -s -p "Entrez votre token GitHub personnel : " GITHUB_TOKEN
    echo
fi
if verify_credentials "$GITHUB_USER" "$GITHUB_TOKEN"; then
    echo "✅ Authentification GitHub réussie."
else
    echo "❌ Authentification GitHub échouée."
    exit 1
fi

CREATED_DIRS=()

log() {
    echo -e "$1"
}
OWNER="maisonnavejul"

# Clonage des dépôts dans /data/apps
cd "$APPS_DIR" || { echo "❌ Impossible d'accéder à $APPS_DIR"; exit 1; }
for repo in "${REPOS_APPS[@]}"; do
    if [[ ! -d "$repo" ]]; then
        repo_url="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${OWNER}/${repo}.git"
        log "📥 Clonage du dépôt $repo dans $APPS_DIR (branche $BRANCH)..."
        sudo -H -u "$EXEC_USER" git clone --branch "$BRANCH" "$repo_url" "$repo"
        if [[ $? -eq 0 ]]; then
            CREATED_DIRS+=("$APPS_DIR/$repo")
        else
            log "❌ Échec du clonage du dépôt : $repo"
        fi
    else
        log "✅ Dépôt déjà cloné: $repo"
        sudo -H -u "$EXEC_USER" git -C "$repo" pull --ff-only || true
    fi
done

# Clonage de Ryvie dans /opt (devient /opt/Ryvie)
# Créer le dossier parent avec les bonnes permissions pour permettre le clonage
for repo in "${REPOS_OPT[@]}"; do
    sudo mkdir -p "$RYVIE_ROOT/$repo"
    sudo chown "$EXEC_USER:$EXEC_USER" "$RYVIE_ROOT/$repo"
done

cd "$RYVIE_ROOT" || { echo "❌ Impossible d'accéder à $RYVIE_ROOT"; exit 1; }
for repo in "${REPOS_OPT[@]}"; do
    if [[ ! -d "$repo/.git" ]]; then
        repo_url="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${OWNER}/${repo}.git"
        log "📥 Clonage du dépôt $repo dans $RYVIE_ROOT (branche $BRANCH)..."
        sudo -H -u "$EXEC_USER" git clone --branch "$BRANCH" "$repo_url" "$repo"
        if [[ $? -eq 0 ]]; then
            CREATED_DIRS+=("$RYVIE_ROOT/$repo")
            # Appliquer les permissions récursives sur le dossier cloné
            sudo chown -R "$EXEC_USER:$EXEC_USER" "$RYVIE_ROOT/$repo"
            log "✅ Permissions appliquées sur $RYVIE_ROOT/$repo"
        else
            log "❌ Échec du clonage du dépôt : $repo"
        fi
    else
        log "✅ Dépôt déjà cloné: $repo"
        sudo -H -u "$EXEC_USER" git -C "$repo" pull --ff-only || true
        # S'assurer que les permissions sont correctes
        sudo chown -R "$EXEC_USER:$EXEC_USER" "$RYVIE_ROOT/$repo" || true
    fi
done

# Vérifier si npm est installé
if command -v npm > /dev/null 2>&1; then
    echo "✅ npm est déjà installé : $(npm --version)"
else
    echo "⚙️ npm n'est pas installé. Installation en cours..."
    install_pkgs npm || {
        echo "❌ Erreur: L'installation de npm a échoué."
        exit 1
    }

    if command -v npm > /dev/null 2>&1; then
        echo "✅ npm a été installé avec succès : $(npm --version)"
    else
        echo "❌ Erreur: L'installation de npm a échoué."
        exit 1
    fi
fi

echo "----------------------------------------------------"
echo "Etape intermédiaire : augmentation des permissions"
echo "----------------------------------------------------"
sudo usermod -aG sudo ryvie

# ⚠️ NE JAMAIS faire chown -R /data (casse les volumes Docker)
# Les permissions sont déjà définies au début du script de manière ciblée
echo "✅ Permissions configurées de manière sécurisée (Docker volumes protégés)"
echo ""
echo ""
echo "------------------------------------------"
echo " Étape 2 : Vérification et installation de Node.js "
echo "------------------------------------------"
echo ""

# Vérifie si Node.js est installé et s'il est à jour (v14 ou plus)
if command -v node > /dev/null 2>&1 && [ "$(node -v | cut -d 'v' -f2 | cut -d '.' -f1)" -ge 14 ]; then
    echo "Node.js est déjà installé : $(node --version)"
else
    echo "Node.js est manquant ou trop ancien. Installation de la version stable avec 'n'..."

    # Installer 'n' si absent
    if ! command -v n > /dev/null 2>&1; then
        echo "Installation de 'n' (Node version manager)..."
        sudo npm install -g n
    fi

    # Installer Node.js stable (la plus récente)
    sudo n stable

    # Corriger la session shell
    export PATH="/usr/local/bin:$PATH"
    hash -r

    # Vérification après installation
    if command -v node > /dev/null 2>&1; then
        echo "Node.js a été installé avec succès : $(node --version)"
    else
        echo "Erreur : l'installation de Node.js a échoué."
        exit 1
    fi
fi

# =====================================================
# 6. Vérification des dépendances
# =====================================================
echo "----------------------------------------------------"
echo "Etape 3: Vérification des dépendances (mode strict pour cette section)"
echo "----------------------------------------------------"
# Activer le comportement "exit on error" uniquement pour l'installation des dépendances
strict_enter
install_pkgs gdisk parted build-essential python3 make g++ ldap-utils
# Vérifier le code de retour de npm install (strict mode assure l'arrêt si npm install échoue)
echo ""
echo "Tous les modules ont été installés avec succès."
strict_exit

# =====================================================

echo "----------------------------------------------------"
echo "Étape 4: Vérification et configuration Docker + containerd (mode strict)"
echo "----------------------------------------------------"
strict_enter

# Defaults si non définis
: "${DOCKER_ROOT:=/data/docker}"
: "${CONTAINERD_ROOT:=/data/containerd}"

if command -v docker >/dev/null 2>&1; then
  echo "Docker est déjà installé : $(docker --version)"
else
  echo "Docker n'est pas installé. L'installation va débuter..."

  ### 🐳 1. Mettre à jour les paquets
  $APT_CMD update
  $APT_CMD upgrade -y

  ### 🐳 2. Installer les dépendances nécessaires
  install_pkgs ca-certificates curl gnupg lsb-release jq 

  ### 🐳 3. Ajouter la clé GPG officielle de Docker (écrase sans prompt)
  sudo mkdir -p /etc/apt/keyrings
  sudo rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL "https://download.docker.com/linux/$( [ "${ID:-}" = "debian" ] && echo "debian" || echo "ubuntu" )/gpg" | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  ### 🐳 4. Ajouter le dépôt Docker (choix debian/ubuntu)
  DOCKER_DISTRO=$( [ "${ID:-}" = "debian" ] && echo "debian" || echo "ubuntu" )
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_DISTRO} ${DISTRO_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  ### 🐳 5. Installer Docker Engine + Docker Compose plugin via apt
  $APT_CMD update -qq
  if ! install_pkgs docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
      echo "⚠️ Impossible d'installer certains paquets Docker via apt — tentative de fallback via le script officiel..."
      if curl -fsSL https://get.docker.com | sudo sh; then
          echo "✅ Docker installé via get.docker.com"
      else
          echo "❌ Échec de l'installation de Docker via apt et get.docker.com. Continuer sans Docker."
      fi
  fi

  # Activer les services Docker/containerd si disponibles
  sudo systemctl enable docker 2>/dev/null || true
  sudo systemctl enable containerd 2>/dev/null || true
fi

# Assure la présence de jq au cas où
command -v jq >/dev/null 2>&1 || install_pkgs jq

echo "Configuration des répertoires de données…"
sudo mkdir -p "$DOCKER_ROOT" "$CONTAINERD_ROOT"
# Droits typiques : docker root dir accessible à root/docker
sudo chown root:docker "$DOCKER_ROOT" || sudo chown root:root "$DOCKER_ROOT"
sudo chmod 750 "$DOCKER_ROOT" || sudo chmod 711 "$DOCKER_ROOT"
# containerd est géré par root
sudo chown root:root "$CONTAINERD_ROOT"
sudo chmod 711 "$CONTAINERD_ROOT"

echo "Arrêt propre des services…"
sudo systemctl stop docker || true
sudo systemctl stop containerd || true

### 🔧 Configurer containerd pour stocker sa data en dehors de /var/lib/containerd
echo "Configuration de containerd (root=${CONTAINERD_ROOT})…"
# Génère un config.toml par défaut si absent
if [ ! -f /etc/containerd/config.toml ]; then
  sudo mkdir -p /etc/containerd
  if command -v containerd >/dev/null 2>&1 && containerd config default >/dev/null 2>&1; then
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  else
    # Configuration minimale au cas où la commande "containerd config default" n'est pas disponible
    sudo tee /etc/containerd/config.toml >/dev/null <<'EOF'
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
EOF
  fi
fi

# Mettre à jour root et state (state par défaut dans /run/containerd)
# On supprime toutes les lignes root existantes (commentées OU non),
# puis on ajoute notre ligne propre tout en haut du fichier.
sudo sed -i '/^\s*#\s*root\s*=\s*".*"/d;/^\s*root\s*=\s*".*"/d' /etc/containerd/config.toml
sudo sed -i '1i root = "'"$CONTAINERD_ROOT"'"' /etc/containerd/config.toml
# Optionnel: déplacer aussi le state (volatile). On laisse par défaut /run/containerd.
# sudo sed -i 's#^\s*state\s*=\s*".*"#state = "/run/containerd"#' /etc/containerd/config.toml

# Migrer l’ancien contenu s’il existe
if [ -d /var/lib/containerd ] && [ "$CONTAINERD_ROOT" != "/var/lib/containerd" ]; then
  echo "Migration de /var/lib/containerd vers $CONTAINERD_ROOT…"
  sudo rsync -aHAXS --delete /var/lib/containerd/ "$CONTAINERD_ROOT"/ || true
  sudo mv /var/lib/containerd "/var/lib/containerd.bak.$(date +%s)" || true
fi

echo "Redémarrage de containerd…"
sudo systemctl daemon-reload || true
sudo systemctl restart containerd || true
# Vérification d'état containerd
if sudo systemctl is-active --quiet containerd; then
  echo "containerd actif."
else
  echo "⚠️ containerd semble inactif."
fi

### 🐳 Configurer Docker pour utiliser $DOCKER_ROOT
echo "Configuration de Docker (data-root=${DOCKER_ROOT})…"
# Mettre à jour /etc/docker/daemon.json de manière fiable sans dépendre de variables d'env dans un sous-shell sudo
sudo mkdir -p /etc/docker
tmp_daemon=$(mktemp)
if [ -f /etc/docker/daemon.json ]; then
  # Utiliser jq pour forcer la clé "data-root". En cas d'échec de jq, on écrit un JSON minimal.
  if jq --arg dr "$DOCKER_ROOT" '."data-root"=$dr' /etc/docker/daemon.json > "$tmp_daemon" 2>/dev/null; then
    :
  else
    echo "{\"data-root\":\"$DOCKER_ROOT\"}" > "$tmp_daemon"
  fi
else
  echo "{\"data-root\":\"$DOCKER_ROOT\"}" > "$tmp_daemon"
fi
sudo mv "$tmp_daemon" /etc/docker/daemon.json

# Migrer l’ancienne data Docker si présente
if [ -d /var/lib/docker ] && [ "$DOCKER_ROOT" != "/var/lib/docker" ]; then
  echo "Migration de /var/lib/docker vers $DOCKER_ROOT…"
  sudo rsync -aHAXS --delete /var/lib/docker/ "$DOCKER_ROOT"/ || true
  sudo mv /var/lib/docker "/var/lib/docker.bak.$(date +%s)" || true
fi

echo "Redémarrage de Docker…"
sudo systemctl daemon-reexec || sudo systemctl daemon-reload
sudo systemctl enable docker 2>/dev/null || true
sudo systemctl restart docker || true

echo "Vérifications…"
# Vérifier le répertoire racine Docker
actual_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")
if [ -n "$actual_root" ]; then
  echo "Docker Root Dir: $actual_root"
  if [ "$actual_root" != "$DOCKER_ROOT" ]; then
    echo "⚠️ Attention: Docker Root Dir ne correspond pas à $DOCKER_ROOT"
  fi
else
  docker info 2>/dev/null | grep -E "Docker Root Dir|Storage Driver" || true
fi
echo "Test 'hello-world'…"
sudo docker run --rm hello-world || echo "⚠️ 'docker run hello-world' a échoué."

# Groupe docker pour l’utilisateur (nécessite reconnexion pour effet)
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker ryvie || true
  echo "ℹ️ Déconnecte/reconnecte-toi (ou 'newgrp docker') pour activer l'appartenance au groupe docker."
fi

echo ""
echo "----------------------------------------------------"
echo "🔧 Fonction de réparation des permissions Docker (si nécessaire)"
echo "----------------------------------------------------"
# Cette fonction permet de réparer les permissions des volumes Docker
# si vous avez accidentellement fait un chown -R sur /data
repair_docker_volumes() {
  echo "⚙️ Réparation des permissions des volumes Docker sensibles..."
  
  # Prometheus (UID 65534:65534 = nobody)
  if docker volume ls | grep -q "prometheus-data"; then
    echo "  🔹 Réparation Prometheus..."
    docker run --rm -v immich-prod_prometheus-data:/prometheus alpine \
      sh -c 'chown -R 65534:65534 /prometheus && chmod -R u+rwX,g+rwX /prometheus' 2>/dev/null || \
      echo "    ⚠️ Volume Prometheus non trouvé ou déjà OK"
  fi
  
  # PostgreSQL rPictures (généralement UID 999:999)
  if docker volume ls | grep -q "pgvecto-rs"; then
    echo "  🔹 Réparation PostgreSQL rPictures..."
    docker run --rm -v app-rpictures_pgvecto-rs:/var/lib/postgresql/data alpine \
      sh -c 'chown -R 999:999 /var/lib/postgresql/data' 2>/dev/null || \
      echo "    ⚠️ Volume PostgreSQL non trouvé ou déjà OK"
  fi
  
  echo "✅ Réparation des volumes terminée"
}

# Décommenter la ligne suivante UNIQUEMENT si vous devez réparer les permissions
# repair_docker_volumes

strict_exit

echo ""
echo "----------------------------------------------------"
echo "Pré-configuration: Génération du mot de passe LDAP"
echo "----------------------------------------------------"

# Générer le mot de passe LDAP en premier (nécessaire pour tous les .env)
LDAP_DIR="$CONFIG_DIR/ldap"
mkdir -p "$LDAP_DIR"
echo "🔐 Génération d'un mot de passe aléatoire pour l'admin LDAP..."
LDAP_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)

# Stocker le mot de passe dans /data/config/ldap/.env
cat > "$LDAP_DIR/.env" <<EOF
LDAP_ADMIN_PASSWORD=$LDAP_ADMIN_PASSWORD
EOF
chmod 600 "$LDAP_DIR/.env"
chown "$EXEC_USER:$EXEC_USER" "$LDAP_DIR/.env" 2>/dev/null || true
echo "✅ Mot de passe admin LDAP généré et stocké dans $LDAP_DIR/.env"

echo ""
echo "----------------------------------------------------"
echo "Étape 5: Installation et Configuration de NetBird "
echo "----------------------------------------------------"

#==========================================
# NetBird Configuration and Setup Script
#==========================================
# Description: Complete NetBird installation, connection, and API registration
# Author: Ryvie Project
# Version: 1.0
#==========================================

MANAGEMENT_URL="https://netbird.ryvie.fr"
API_ENDPOINT="https://api.ryvie.fr/api/register"
SETUPKEY_API_ENDPOINT="https://api.ryvie.fr/api/generate-setupkey"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================="
echo "NetBird Isolated Network Setup"
echo -e "==================================================${NC}"

# Call the API to generate setup key automatically
echo -e "${GREEN}[1/1]${NC} Generating NetBird setup key via API..."
SETUPKEY_RESPONSE=$(curl -s -X POST "$SETUPKEY_API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{}')

# Extract values from API response
SETUP_KEY_VALUE=$(echo "$SETUPKEY_RESPONSE" | jq -r '.setupKey // empty')
GROUP_ID=$(echo "$SETUPKEY_RESPONSE" | jq -r '.groupId // empty')
GROUP_NAME=$(echo "$SETUPKEY_RESPONSE" | jq -r '.groupName // empty')
TCP_POLICY_ID=$(echo "$SETUPKEY_RESPONSE" | jq -r '.tcpPolicyId // empty')

if [ -z "$SETUP_KEY_VALUE" ] || [ "$SETUP_KEY_VALUE" = "null" ]; then
  echo -e "${RED}ERROR: Failed to generate setup key via API${NC}"
  echo "Response: $SETUPKEY_RESPONSE"
  exit 1
fi

echo "      ✓ Setup key generated: $SETUP_KEY_VALUE"
echo "      ✓ Group created: $GROUP_ID ($GROUP_NAME)"
echo "      ✓ TCP policy created: $TCP_POLICY_ID"
echo ""
echo -e "${BLUE}=================================================="
echo "SETUP COMPLETE ✓"
echo -e "==================================================${NC}"
echo ""
echo -e "${GREEN}Group ID:${NC} $GROUP_ID"
echo -e "${GREEN}Group Name:${NC} $GROUP_NAME"
echo ""
echo -e "${GREEN}SETUP KEY (share with other devices):${NC}"
echo -e "${YELLOW}$SETUP_KEY_VALUE${NC}"
echo ""
echo -e "${GREEN}✓ Peers in this group CAN communicate with each other${NC}"
echo -e "${RED}✗ Isolated from All group (external networks)${NC}"
echo ""
echo -e "${BLUE}==================================================${NC}"

ENV_FILE="$CONFIG_DIR/netbird/.env"
sudo mkdir -p "$CONFIG_DIR/netbird"
sudo touch "$ENV_FILE"
sudo chown "$EXEC_USER:$EXEC_USER" "$ENV_FILE" || true
tmp_env="$(mktemp)"
if [ -s "$ENV_FILE" ]; then
  grep -vE '^(NETBIRD_SETUP_KEY|NETBIRD_IP)=' "$ENV_FILE" > "$tmp_env" 2>/dev/null || true
fi
printf 'NETBIRD_SETUP_KEY=%s\n%s\n' "$SETUP_KEY_VALUE" >> "$tmp_env"
sudo mv "$tmp_env" "$ENV_FILE"
sudo chmod 600 "$ENV_FILE" || true
echo "✅ NetBird setup key and IP written to $ENV_FILE"

readonly MANAGEMENT_URL="https://netbird.ryvie.fr"
readonly SETUP_KEY=$SETUP_KEY_VALUE

readonly API_ENDPOINT="https://api.ryvie.fr/api/register"
readonly NETBIRD_INTERFACE="wt0"
readonly TARGET_DIR="$RYVIE_ROOT/Ryvie/Ryvie-Front/src/config"
RDRIVE_DIR="$APPS_DIR/Ryvie-rDrive/tdrive"

# Persistance NetBird sous $DATA_ROOT/netbird (idempotent)

sudo mkdir -p "$DATA_ROOT/netbird"

#==========================================
# COLORS FOR OUTPUT
#==========================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#==========================================
# LOGGING FUNCTIONS
#==========================================
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_debug()   { echo -e "${BLUE}[DEBUG]${NC} $1"; }

#==========================================
# UTILITY FUNCTIONS
#==========================================

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if running as root
is_root() {
    [ "$EUID" -eq 0 ]
}

# Get machine ID
get_machine_id() {
    if [ -f /etc/machine-id ]; then
        cat /etc/machine-id
    else
        uuidgen 2>/dev/null || echo "$(hostname)-$(date +%s)"
    fi
}

#==========================================
# SYSTEM DETECTION
#==========================================
detect_system() {
    local os arch
    
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case $arch in
        x86_64)          arch="amd64" ;;
        aarch64|arm64)   arch="arm64" ;;
        armv7l)          arch="armv7" ;;
        *) 
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    log_info "Detected system: $os/$arch"
    
    # Export for global use
    export DETECTED_OS="$os"
    export DETECTED_ARCH="$arch"
}

#==========================================
# NETBIRD FUNCTIONS
#==========================================
persist_netbird_data() {
    local src="/var/lib/netbird"
    local dst="${DATA_ROOT:-/data}/netbird"

    # S'assurer que le dossier de destination existe
    sudo mkdir -p "$dst"

    # Si déjà lié → rien à faire
    if [ -L "$src" ]; then
        log_info "NetBird data already linked to $dst"
        return 0
    fi

    # Stopper le service s'il existe
    if systemctl list-unit-files 2>/dev/null | grep -q '^netbird\.service'; then
        sudo systemctl stop netbird 2>/dev/null || true
    fi

    # Migrer l'éventuel contenu existant
    if [ -d "$src" ]; then
        sudo rsync -a "$src"/ "$dst"/ 2>/dev/null || true
        sudo mv "$src" "/var/lib/netbird.bak.$(date +%s)" 2>/dev/null || sudo rm -rf "$src"
    fi

    # Créer le lien symbolique vers /data
    sudo ln -s "$dst" "$src" 2>/dev/null || true

    # Redémarrer si le service existe
    if systemctl list-unit-files 2>/dev/null | grep -q '^netbird\.service'; then
        sudo systemctl start netbird 2>/dev/null || true
    fi

    return 0
}

check_netbird_installed() {
    command_exists netbird
}

install_netbird() {
    log_info "Installing NetBird using official install script..."
    
    if curl -fsSL https://pkgs.netbird.io/install.sh | sh; then
        log_info "NetBird installed successfully"
        # S'assurer que le service est activé et démarré
        sudo systemctl enable --now netbird 2>/dev/null || true
    else
        log_error "NetBird installation failed"
        exit 1
    fi
}

check_netbird_connected() {
    if netbird status &> /dev/null; then
        local status
        status=$(netbird status | grep "Management" | grep "Connected" || true)
        [ -n "$status" ]
    else
        return 1
    fi
}

connect_netbird() {
    log_info "Connecting to NetBird management server..."
    
    # S'assurer que le service est actif
    sudo systemctl enable --now netbird 2>/dev/null || true

    # Diagnostic de connectivité Management/API (best-effort)
    if command -v curl >/dev/null 2>&1; then
        http_mgmt=$(curl -s -o /dev/null -w "%{http_code}" "$MANAGEMENT_URL" || echo "000")
        http_api=$(curl -s -o /dev/null -w "%{http_code}" "$API_ENDPOINT" || echo "000")
        log_info "Connectivity check: MANAGEMENT_URL=$http_mgmt API_ENDPOINT=$http_api"
    fi

    # Stop any existing connection
    sudo netbird down &> /dev/null || true
    
    # Try multiple times to bring up the connection
    local attempts=5
    local delay=5
    local i=1
    while [ $i -le $attempts ]; do
        log_info "netbird up attempt $i/$attempts..."
        if sudo netbird up --management-url "$MANAGEMENT_URL" --setup-key "$SETUP_KEY"; then
            sleep 5
            if check_netbird_connected; then
                log_info "NetBird connected successfully"
                return 0
            fi
        fi
        log_warning "NetBird up failed or not connected yet. Retrying in ${delay}s..."
        sleep $delay
        i=$((i+1))
    done

    # Diagnostics avant abandon
    log_error "Failed to connect to NetBird after ${attempts} attempts"
    sudo systemctl status netbird --no-pager -l 2>/dev/null | tail -n 50 || true
    sudo journalctl -u netbird --no-pager -n 100 2>/dev/null || true
    exit 1
}

#==========================================
# NETWORK INTERFACE FUNCTIONS
#==========================================

wait_for_interface() {
    local max_attempts=30
    local attempt=1
    local ip

    log_info "Waiting for $NETBIRD_INTERFACE interface to be ready..."

    while [ $attempt -le $max_attempts ]; do
        if ip link show "$NETBIRD_INTERFACE" &> /dev/null; then
            ip=$(get_interface_ip "$NETBIRD_INTERFACE")
            if [ -n "$ip" ]; then
                log_info "Interface $NETBIRD_INTERFACE is ready with IP: $ip"
                return 0
            fi
        fi
        
        log_warning "Attempt $attempt/$max_attempts: Waiting for interface..."
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "Interface $NETBIRD_INTERFACE did not become ready in time"
    return 1
}

get_interface_ip() {
    local interface="$1"
    ip -4 addr show dev "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

# Helper: obtenir l'IP NetBird ou fallback sur localhost
get_netbird_ip() {
    local ip
    ip=$(get_interface_ip "$NETBIRD_INTERFACE")
    if [ -z "$ip" ]; then
        echo "localhost"
    else
        echo "$ip"
    fi
}

#==========================================
# API REGISTRATION FUNCTIONS
#==========================================

register_with_api() {
    log_info "Registering with API..."

    local ip machine_id response http_code body
    
    ip=$(get_interface_ip "$NETBIRD_INTERFACE")
    if [ -z "$ip" ]; then
        log_error "Could not find IP for interface $NETBIRD_INTERFACE"
        exit 1
    fi
    
    log_info "Using IP address: $ip"
    machine_id=$(get_machine_id)
    
    # Prepare API request
    local json_payload
    json_payload=$(cat <<EOF
{
    "machineId": "$machine_id",
    "arch": "$DETECTED_ARCH",
    "os": "$DETECTED_OS",
    "backendHost": "$ip",
    "services": [
       "rtransfer", "rdrop"
    ]
}
EOF
)

    # Make API request (sauvegarde sous /data/config/netbird)
    mkdir -p "$CONFIG_DIR/netbird"
    local netbird_tmp="$CONFIG_DIR/netbird/netbird_data"
    response=$(curl -s -w "%{http_code}" -o "$netbird_tmp" -X POST "$API_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    http_code="${response: -3}"
    body=$(cat "$netbird_tmp" 2>/dev/null || echo "")

    # Handle response
    if echo "$body" | grep -q '"status":"already_exists"'; then
        log_info "BackendHost $ip is already registered, skipping registration."
        return 0
    fi

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log_info "Successfully registered with API"
        process_api_response
    else
        log_error "Failed to register with API (HTTP $http_code)"
        log_error "Response body saved in: $netbird_tmp"
        exit 1
    fi
}

process_api_response() {
    local netbird_cfg_dir="$CONFIG_DIR/netbird"
    local json_file="$netbird_cfg_dir/netbird-data.json"
    local netbird_tmp="$netbird_cfg_dir/netbird_data"

    mkdir -p "$netbird_cfg_dir"
    if [ -f "$netbird_tmp" ]; then
        mv "$netbird_tmp" "$json_file"
    fi

    if [ -f "$json_file" ]; then
        log_info "Copying $(basename "$json_file") to $TARGET_DIR"
        # Créer le répertoire cible avec sudo et donner les permissions à l'utilisateur
        sudo mkdir -p "$TARGET_DIR"
        sudo chown -R "$EXEC_USER:$EXEC_USER" "$TARGET_DIR"
        sudo chmod 755 "$TARGET_DIR"
        
        # Copier le fichier en tant qu'utilisateur
        if sudo -u "$EXEC_USER" cp "$json_file" "$TARGET_DIR/"; then
            log_info "Successfully copied $(basename "$json_file") to $TARGET_DIR"
            # S'assurer que le fichier copié a les bonnes permissions
            sudo chown "$EXEC_USER:$EXEC_USER" "$TARGET_DIR/$(basename "$json_file")"
            sudo chmod 644 "$TARGET_DIR/$(basename "$json_file")"
        else
            log_warning "Failed to copy $(basename "$json_file") to $TARGET_DIR"
        fi
    fi
}

#==========================================
# ENVIRONMENT CONFIGURATION FUNCTIONS
#==========================================

install_jq() {
    if command_exists jq; then
        return 0
    fi
    
    log_info "Installing jq..."
    
    if command_exists apt; then
        sudo apt update && sudo apt install -y jq
    elif command_exists brew; then
        brew install jq
    else
        log_error "Cannot install jq automatically. Please install jq manually."
        exit 1
    fi
}

# Fonction pour générer le fichier .env
generate_env_file() {
    local json_file="$CONFIG_DIR/netbird/netbird-data.json"
    
    log_info "=== Début de la phase de configuration d'environnement ==="
    log_info "Génération de la configuration d'environnement..."
    
    # Vérifier si le fichier JSON existe dans /data/config/netbird
    if [ ! -f "$json_file" ]; then
        log_error "netbird-data.json introuvable dans $CONFIG_DIR/netbird"
        exit 1
    fi
    
    # S'assurer que jq est disponible
    install_jq
    
    # Extraire les domaines du fichier JSON
    local rtransfer rdrop
    
    rtransfer=$(jq -r '.domains.rtransfer' "$json_file")
    rdrop=$(jq -r '.domains.rdrop' "$json_file")
    
    # Valider l'extraction
    if [ "$rtransfer" = "null" ] || [ "$rdrop" = "null" ]; then
        log_error "Impossible d'extraire les domaines de $json_file. Vérifiez la structure JSON."
        log_error "Attendu: .domains.rtransfer et .domains.rdrop"
        exit 1
    fi
    
    # Générer le fichier .env sous /data/config pour rtransfer et rdrop
    mkdir -p "$CONFIG_DIR/rtransfer" "$CONFIG_DIR/rdrop"
    
    # Fichier .env pour rtransfer
    local rtransfer_env="$CONFIG_DIR/rtransfer/.env"
    cat > "$rtransfer_env" << EOF
APP_URL=https://$rtransfer
EOF
    
    # Fichier .env pour rdrop
    local rdrop_env="$CONFIG_DIR/rdrop/.env"
    cat > "$rdrop_env" << EOF
APP_URL=https://$rdrop
EOF
    
    log_info "Fichiers .env générés pour rtransfer et rdrop"

    # --- Déploiement dans les répertoires des apps ---
    # rtransfer
    local rtransfer_app_dir="$APPS_DIR/Ryvie-rTransfer"
    if [ -d "$rtransfer_app_dir" ]; then
        local rtransfer_app_env="$rtransfer_app_dir/.env"
        [ -f "$rtransfer_app_env" ] && cp "$rtransfer_app_env" "$rtransfer_app_env.bak.$(date +%s)" || true
        cp -f "$rtransfer_env" "$rtransfer_app_env"
        chmod 600 "$rtransfer_app_env" || true
        chown "$EXEC_USER:$EXEC_USER" "$rtransfer_app_env" 2>/dev/null || true
        log_info "✅ .env déployé → $rtransfer_app_env"
    fi
    
    # rdrop
    local rdrop_app_dir="$APPS_DIR/Ryvie-rdrop"
    if [ -d "$rdrop_app_dir" ]; then
        local rdrop_app_env="$rdrop_app_dir/.env"
        [ -f "$rdrop_app_env" ] && cp "$rdrop_app_env" "$rdrop_app_env.bak.$(date +%s)" || true
        cp -f "$rdrop_env" "$rdrop_app_env"
        chmod 600 "$rdrop_app_env" || true
        chown "$EXEC_USER:$EXEC_USER" "$rdrop_app_env" 2>/dev/null || true
        log_info "✅ .env déployé → $rdrop_app_env"
    fi

    # --- rDrive : génération du .env avec l'IP NetBird ---
    local rdrive_app_dir="$APPS_DIR/Ryvie-rDrive/tdrive"
    if [ -d "$rdrive_app_dir" ]; then
        log_info "Génération du .env pour rDrive..."
        
        # Créer le dossier config/rdrive
        mkdir -p "$CONFIG_DIR/rdrive"
        local rdrive_env="$CONFIG_DIR/rdrive/.env"
        
        # Récupérer l'IP NetBird
        local netbird_ip
        netbird_ip=$(get_netbird_ip)
        
        # Charger le mot de passe LDAP depuis le fichier .env
        local ldap_admin_password=""
        if [ -f "$CONFIG_DIR/ldap/.env" ]; then
            source "$CONFIG_DIR/ldap/.env"
            ldap_admin_password="$LDAP_ADMIN_PASSWORD"
        fi
        
        # Générer le fichier .env dans /data/config/rdrive
        cat > "$rdrive_env" << EOF
REACT_APP_FRONTEND_URL=http://$netbird_ip:3010
REACT_APP_BACKEND_URL=http://$netbird_ip:4000
REACT_APP_WEBSOCKET_URL=ws://$netbird_ip:4000/ws
REACT_APP_ONLYOFFICE_CONNECTOR_URL=http://$netbird_ip:5000
REACT_APP_ONLYOFFICE_DOCUMENT_SERVER_URL=http://$netbird_ip:8090
LDAP_BIND_PASSWORD=$ldap_admin_password
DROPBOX_APPKEY=fuv2aur5vtmg0r3
DROPBOX_APPSECRET=ejsdcf3b51q8hvf
GOOGLE_CLIENT_ID=758017908766-8586ul049ht0h10vgp779dskk4riu7ug.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=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
EOF
        
        log_info "✅ .env rDrive généré → $rdrive_env"
        
        # Déployer dans le répertoire de l'app
        local rdrive_app_env="$rdrive_app_dir/.env"
        [ -f "$rdrive_app_env" ] && cp "$rdrive_app_env" "$rdrive_app_env.bak.$(date +%s)" || true
        cp -f "$rdrive_env" "$rdrive_app_env"
        chmod 600 "$rdrive_app_env" || true
        chown "$EXEC_USER:$EXEC_USER" "$rdrive_app_env" 2>/dev/null || true
        log_info "✅ .env déployé → $rdrive_app_env"
    else
        log_info "⚠️ Ryvie-rDrive non trouvé, skip de la génération du .env rDrive"
    fi

    log_info "Configuration d'environnement terminée"
}

#==========================================
# VALIDATION FUNCTIONS
#==========================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if running as root when needed
    if ! is_root && ! check_netbird_installed; then
        log_error "Please run this script as root or with sudo for installation"
        exit 1
    fi
    
    # Check required directories exist or can be created
    if [ ! -d "$(dirname "$TARGET_DIR")" ] && ! mkdir -p "$(dirname "$TARGET_DIR")" 2>/dev/null; then
        log_warning "Cannot create target directory structure: $TARGET_DIR"
    fi
    
    if [ ! -d "$(dirname "$RDRIVE_DIR")" ]; then
        log_warning "RDrive directory structure not found: $RDRIVE_DIR"
    fi
}

#==========================================
# MAIN EXECUTION FUNCTIONS
#==========================================

main_netbird_setup() {
    log_info "=== Starting NetBird Setup Phase ==="
    
    # Install NetBird if needed
    if ! check_netbird_installed; then
        log_info "NetBird not found, installing..."
        install_netbird
    else
        log_info "NetBird is already installed"
    fi
    
    persist_netbird_data

    # Connect NetBird if needed
    if ! check_netbird_connected; then
        connect_netbird
    else
        log_info "NetBird is already connected"
    fi

    # Wait for interface to be ready
    if ! wait_for_interface; then
        log_error "NetBird interface setup failed"
        exit 1
    fi

    # Register with API
    register_with_api
    
    log_info "=== NetBird Setup Phase Completed ==="
}

main_env_setup() {
    log_info "=== Starting Environment Configuration Phase ==="
    
    generate_env_file
    
    log_info "=== Environment Configuration Phase Completed ==="
}

main() {
    echo "🚀 Launching NetBird Configuration..."
    
    # Use RYVIE_ROOT for NetBird config
    cd "$RYVIE_ROOT" || { log_error "❌ Impossible d'accéder à $RYVIE_ROOT"; exit 1; }
    
    # Validate environment
    validate_prerequisites
    
    # Detect system
    detect_system 
    
    # Execute main phases
    main_netbird_setup
    main_env_setup
    
    log_info "🎉 NetBird setup completed successfully!"
    log_info "All configurations have been generated and services are ready."
}

#==========================================
# SCRIPT ENTRY POINT
#==========================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
sudo chown ryvie:ryvie /data/config/netbird/.env

echo ""
echo "----------------------------------------------------"
echo "Étape 6: Installation de Redis"
echo "----------------------------------------------------"

# Vérifier si Redis est déjà installé
if command -v redis-server > /dev/null 2>&1; then
    echo "Redis est déjà installé : $(redis-server --version)"
else
    echo "Installation de Redis (redis-server)..."
    install_pkgs redis-server || { echo "❌ Échec de l'installation de Redis"; }
    # Configurer Redis pour systemd si nécessaire
    if [ -f /etc/redis/redis.conf ]; then
        sudo sed -i 's/^supervised .*/supervised systemd/' /etc/redis/redis.conf
    fi
    # Activer et démarrer Redis
    sudo systemctl enable --now redis-server
fi

# Vérifier l'état du service Redis
if systemctl is-active --quiet redis-server; then
    echo "Redis est en cours d'exécution."
else
    echo "Tentative de démarrage de Redis..."
    sudo systemctl start redis-server || echo "⚠️ Impossible de démarrer Redis automatiquement."
fi

# Test simple avec redis-cli si disponible
if command -v redis-cli > /dev/null 2>&1; then
    RESP=$(redis-cli ping 2>/dev/null || true)
    if [ "$RESP" = "PONG" ]; then
        echo "✅ Test Redis OK (PONG)"
    else
        echo "⚠️ Test Redis échoué (redis-cli ping ne répond pas PONG)"
    fi
fi

echo ""
 echo "--------------------------------------------------"
 echo "Etape 7: Ajout de l'utilisateur ($EXEC_USER) au groupe docker "
 echo "--------------------------------------------------"
 echo ""
 
 # Vérifier si docker est disponible avant d'ajouter l'utilisateur au groupe
 if command -v docker > /dev/null 2>&1; then
     # Créer le groupe docker si nécessaire
     if ! getent group docker > /dev/null 2>&1; then
         sudo groupadd docker || true
     fi

     if id -nG "$EXEC_USER" | grep -qw "docker"; then
         echo "L'utilisateur $EXEC_USER est déjà membre du groupe docker."
     else
         sudo usermod -aG docker "$EXEC_USER"
         echo "L'utilisateur $EXEC_USER a été ajouté au groupe docker."
         echo "Veuillez redémarrer votre session pour appliquer définitivement les changements."
     fi
 else
     echo "⚠️ Docker n'est pas installé — saut de l'ajout de l'utilisateur au groupe docker."
 fi

  echo "-----------------------------------------------------"
  echo "Etape 8: Installation et démarrage de Portainer"
  echo "-----------------------------------------------------"
  
# Si Docker absent, sauter Portainer
if command -v docker > /dev/null 2>&1; then
  # Lancer Portainer uniquement s'il n'existe pas déjà
  if ! sudo docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then
    sudo mkdir -p "$DATA_ROOT/portainer"
    sudo docker run -d \
      --name portainer \
      --restart=always \
      -p 8000:8000 \
      -p 9443:9443 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$DATA_ROOT/portainer":/data \
      portainer/portainer-ce:latest
  else
    echo "Portainer existe déjà. Vérification de l'état..."
    if ! sudo docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
      sudo docker start portainer
    fi
  fi
else
  echo "⚠️ Portainer ignoré : Docker non installé."
fi
  
echo "-----------------------------------------------------"
echo "Etape 9: Ip du cloud Ryvie ryvie.local "
echo "-----------------------------------------------------"

# Installer avahi via la fonction d'installation (compatible Debian)
install_pkgs avahi-daemon avahi-utils || true
sudo systemctl enable --now avahi-daemon
sudo sed -i 's/^#\s*host-name=.*/host-name=ryvie/' /etc/avahi/avahi-daemon.conf || true
sudo systemctl restart avahi-daemon || true

echo ""
echo "-----------------------------------------------------"
echo "Étape 10: Configuration d'OpenLDAP avec Docker Compose"
echo "-----------------------------------------------------"

# 1. Créer le dossier ldap sous /data/config et s'y positionner
LDAP_DIR="$CONFIG_DIR/ldap"
mkdir -p "$LDAP_DIR"
cd "$LDAP_DIR"

# 2. Créer le fichier docker-compose.yml pour lancer OpenLDAP avec le mot de passe généré
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  openldap:
    image: julescloud/ryvieldap:latest
    container_name: openldap
    environment:
      - LDAP_ADMIN_USERNAME=admin
      - LDAP_ADMIN_PASSWORD=$LDAP_ADMIN_PASSWORD
      - LDAP_ROOT=dc=example,dc=org
    ports:
      - "389:1389"  # Port LDAP
      - "636:1636"  # Port LDAP sécurisé
    networks:
      my_custom_network:
    volumes:
      - openldap_data:/bitnami/openldap
    restart: unless-stopped

volumes:
  openldap_data:

networks:
  my_custom_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
EOF

# 3. Lancer le conteneur OpenLDAP
sudo docker compose up -d

# 4. Attendre que le conteneur soit prêt
echo "⏳ Attente de la disponibilité du service OpenLDAP..."
until ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" -b "dc=example,dc=org" >/dev/null 2>&1; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ OpenLDAP est prêt."

# 5. Supprimer d'anciens utilisateurs et groupes indésirables
cat <<'EOF' > delete-entries.ldif
dn: cn=user01,ou=users,dc=example,dc=org
changetype: delete

dn: cn=user02,ou=users,dc=example,dc=org
changetype: delete

dn: cn=readers,ou=groups,dc=example,dc=org
changetype: delete
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" -f delete-entries.ldif

# Nettoyer le fichier temporaire
rm -f delete-entries.ldif

# 6. Créer les groupes via add-groups.ldif
cat <<'EOF' > add-groups.ldif
# Groupe admins
dn: cn=admins,ou=users,dc=example,dc=org
objectClass: groupOfNames
cn: admins
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" -f add-groups.ldif

# Nettoyer le fichier temporaire
rm -f add-groups.ldif

# ==================================================================
# Partie ACL : Configuration de l'accès read-only et des droits admins
# ==================================================================

echo ""
echo "-----------------------------------------------------"
echo "Configuration de l'utilisateur read-only et de ses ACL"
echo "-----------------------------------------------------"

# 1. Créer le fichier ACL lecture seule
cat <<'EOF' > acl-read-only.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to dn.subtree="ou=users,dc=example,dc=org"
  by dn.exact="cn=read-only,ou=users,dc=example,dc=org" read
  by * none
EOF

# 2. Créer l'utilisateur read-only
cat <<'EOF' > read-only-user.ldif
dn: cn=read-only,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
cn: read-only
sn: Read
uid: read-only
userPassword: readpassword
EOF

echo "Ajout de l'utilisateur read-only..."
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" -f read-only-user.ldif

# Nettoyer le fichier temporaire
rm -f read-only-user.ldif

echo "Copie du fichier ACL read-only dans le conteneur OpenLDAP..."
sudo docker cp acl-read-only.ldif openldap:/tmp/acl-read-only.ldif

echo "Application de la configuration ACL read-only..."
sudo docker exec -it openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl-read-only.ldif

# Nettoyer le fichier temporaire
rm -f acl-read-only.ldif

echo "Test de l'accès en lecture seule avec l'utilisateur read-only..."
ldapsearch -x -D "cn=read-only,ou=users,dc=example,dc=org" -w readpassword -b "ou=users,dc=example,dc=org" "(objectClass=*)"

# --- ACL pour admins (droits écriture) ---
echo ""
echo "-----------------------------------------------------"
echo "Configuration des droits d'écriture pour le groupe admins"
echo "-----------------------------------------------------"

cat <<'EOF' > acl-admin-write.ldif
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to dn.subtree="ou=users,dc=example,dc=org"
  by group.exact="cn=admins,ou=users,dc=example,dc=org" write
  by * read
EOF

echo "Copie du fichier acl-admin-write.ldif dans le conteneur OpenLDAP..."
sudo docker cp acl-admin-write.ldif openldap:/tmp/acl-admin-write.ldif

echo "Application de la configuration ACL (droits d'écriture pour le groupe admins)..."
sudo docker exec -it openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl-admin-write.ldif

# Nettoyer le fichier temporaire
rm -f acl-admin-write.ldif

echo "✅ Configuration ACL pour le groupe admins appliquée."
echo "🧹 Fichiers LDIF temporaires supprimés."

 echo " ( à implémenter non mis car mdp dedans )"
echo ""
echo ""
echo "-----------------------------------------------------"
echo "Étape 11: Installation et lancement du Ryvie-Back et Front-end"
echo "-----------------------------------------------------"

# S'assurer d'être dans le répertoire de travail
cd "$RYVIE_ROOT" || { echo "❌ RYVIE_ROOT introuvable: $RYVIE_ROOT"; exit 1; }

# Vérifier la présence du dépôt Ryvie
if [ ! -d "Ryvie" ]; then
    echo "❌ Le dépôt 'Ryvie' est introuvable dans $RYVIE_ROOT. Assurez-vous qu'il a été cloné plus haut."
    exit 1
fi

# Aller dans le dossier Ryvie-Back
cd "Ryvie/Ryvie-Back" || { echo "❌ Dossier 'Ryvie/Ryvie-Back' introuvable"; exit 1; }

# Vérifier si .env existe, sinon le créer
if [ ! -f ".env" ] && [ ! -L ".env" ]; then
  echo "⚠️ Aucun .env trouvé. Création d'un fichier .env par défaut sous $CONFIG_DIR/backend-view et symlink local..."
  mkdir -p "$CONFIG_DIR/backend-view"
  
  # Charger le mot de passe LDAP depuis le fichier .env
  if [ -f "$CONFIG_DIR/ldap/.env" ]; then
    source "$CONFIG_DIR/ldap/.env"
  else
    echo "❌ Fichier $CONFIG_DIR/ldap/.env introuvable"
    exit 1
  fi
  
  # Générer les clés de sécurité aléatoires
  echo "🔐 Génération des clés de sécurité pour le backend..."
  ENCRYPTION_KEY=$(openssl rand -base64 32)
  JWT_ENCRYPTION_KEY=$(openssl rand -base64 32)
  JWT_SECRET=$(openssl rand -hex 64)
  
  cat > "$CONFIG_DIR/backend-view/.env" <<EOL
PORT=3002
REDIS_URL=redis://127.0.0.1:6379
ENCRYPTION_KEY=$ENCRYPTION_KEY
JWT_ENCRYPTION_KEY=$JWT_ENCRYPTION_KEY
JWT_SECRET=$JWT_SECRET
# Configuration LDAP
LDAP_URL=ldap://localhost:389
LDAP_BIND_DN=cn=read-only,ou=users,dc=example,dc=org
LDAP_BIND_PASSWORD=readpassword
LDAP_USER_SEARCH_BASE=ou=users,dc=example,dc=org
LDAP_GROUP_SEARCH_BASE=ou=users,dc=example,dc=org
LDAP_ADMIN_GROUP=cn=admins,ou=users,dc=example,dc=org
LDAP_USER_GROUP=cn=users,ou=users,dc=example,dc=org
LDAP_GUEST_GROUP=cn=guests,ou=users,dc=example,dc=org

# Security Configuration
DEFAULT_EMAIL_DOMAIN=example.org
AUTH_RATE_LIMIT_WINDOW_MS=900000
AUTH_RATE_LIMIT_MAX_ATTEMPTS=5
API_RATE_LIMIT_WINDOW_MS=900000
API_RATE_LIMIT_MAX_REQUESTS=100
BRUTE_FORCE_MAX_ATTEMPTS=5
BRUTE_FORCE_BLOCK_DURATION_MS=900000
ENABLE_SECURITY_LOGGING=true
LOG_FAILED_ATTEMPTS=true

# Session Security
SESSION_TIMEOUT_MS=3600000
MAX_CONCURRENT_SESSIONS=3

# Production Security (set to true for production)
FORCE_HTTPS=false
ENABLE_HELMET=true
ENABLE_CORS_CREDENTIALS=false

# Configuration LDAP Admin (mot de passe généré automatiquement)
LDAP_ADMIN_BIND_DN=cn=admin,dc=example,dc=org
LDAP_ADMIN_BIND_PASSWORD=$LDAP_ADMIN_PASSWORD
EOL
  # Créer un symlink local .env vers /data/config pour compatibilité
  ln -sf "$CONFIG_DIR/backend-view/.env" .env
  echo "✅ Fichier .env par défaut créé et lié: $CONFIG_DIR/backend-view/.env -> $(pwd)/.env"
fi

# Installer PM2 globalement si ce n'est pas déjà fait
if ! command -v pm2 &> /dev/null; then
    echo "📦 Installation de PM2..."
    sudo npm install -g pm2 || { echo "❌ Échec de l'installation de PM2"; exit 1; }
fi

# Installer les dépendances backend
echo "📦 Installation des dépendances backend (npm install)"
sudo -u "$EXEC_USER" npm install || { echo "❌ npm install a échoué"; exit 1; }

# Frontend setup
echo "🚀 Configuration du frontend..."
cd "$RYVIE_ROOT/Ryvie/Ryvie-Front" || { echo "❌ Failed to navigate to frontend directory"; exit 1; }

# S'assurer que l'utilisateur a les permissions sur le répertoire frontend
echo "🔒 Configuration des permissions du frontend..."
sudo chown -R "$EXEC_USER:$EXEC_USER" "$RYVIE_ROOT/Ryvie/Ryvie-Front"
sudo chmod -R u+rwX "$RYVIE_ROOT/Ryvie/Ryvie-Front"

echo "📦 Installation des dépendances frontend..."
sudo -u "$EXEC_USER" npm install || { echo "❌ npm install failed"; exit 1; }

# Installer serve pour la production
echo "📦 Installation de serve pour le mode production..."
sudo -u "$EXEC_USER" npm install --save-dev serve || { echo "❌ Installation de serve échouée"; exit 1; }

# Lancer le script de production
echo "🚀 Lancement de Ryvie en mode PRODUCTION..."
cd "$RYVIE_ROOT/Ryvie" || { echo "❌ Impossible d'accéder à $RYVIE_ROOT/Ryvie"; exit 1; }

# Rendre les scripts exécutables
chmod +x scripts/*.sh

# Lancer le script prod.sh
sudo -u "$EXEC_USER" bash scripts/prod.sh || { echo "❌ Échec du lancement en mode production"; exit 1; }

# Configurer PM2 pour le démarrage automatique
sudo pm2 startup systemd -u "$EXEC_USER" --hp "$EXEC_HOME"
sudo -u "$EXEC_USER" pm2 save

echo "✅ Installation et démarrage terminés!"
echo ""
echo "📊 Services lancés en mode PRODUCTION:"
echo "   - Backend:  http://localhost:3002 (Node.js compilé)"
echo "   - Frontend: http://localhost:3000 (serve statique)"
echo ""
echo "📝 Logs:"
echo "   - Backend:  $LOG_DIR/backend-prod-*.log"
echo "   - Frontend: $LOG_DIR/frontend-prod-*.log"
echo ""
echo "ℹ️ Commandes utiles:"
echo "   - Voir les logs: pm2 logs"
echo "   - Rebuilder: $RYVIE_ROOT/Ryvie/scripts/rebuild-prod.sh"
echo "   - Arrêter tout: pm2 stop all"
echo "   - Statut: pm2 status"
echo ""
echo "💡 Consommation en mode PRODUCTION: ~200MB RAM"
echo "-----------------------------------------------------"
echo "Étape 12: Installation de Ryvie rPictures"
echo "-----------------------------------------------------"
# 1. Se placer dans le dossier des applications (APPS_DIR défini en haut)
echo "📁 Dossier sélectionné : $APPS_DIR"
cd "$APPS_DIR" || { echo "❌ Impossible d'accéder à $APPS_DIR"; exit 1; }

# 2. Cloner le dépôt si pas déjà présent
if [ -d "Ryvie-rPictures" ]; then
    echo "✅ Le dépôt Ryvie-rPictures existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rPictures..."
    sudo -H -u "$EXEC_USER" git clone https://github.com/maisonnavejul/Ryvie-rPictures.git
    if [ $? -ne 0 ]; then
        echo "❌ Échec du clonage du dépôt. Arrêt du script."
        exit 1
    fi
fi


# 3. Se placer dans le dossier docker
cd "$APPS_DIR/Ryvie-rPictures/docker"

# 4. Créer le fichier .env avec les variables nécessaires
echo "📝 Création du fichier .env..."

# Charger le mot de passe LDAP depuis le fichier .env
if [ -f "$CONFIG_DIR/ldap/.env" ]; then
  source "$CONFIG_DIR/ldap/.env"
else
  echo "❌ Fichier $CONFIG_DIR/ldap/.env introuvable"
  exit 1
fi

cat <<EOF > .env
# The location where your uploaded files are stored
UPLOAD_LOCATION=./library

# The location where your database files are stored. Network shares are not supported for the database
DB_DATA_LOCATION=./postgres

# To set a timezone, uncomment the next line and change Etc/UTC to a TZ identifier from this list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List
# TZ=Etc/UTC

# The Immich version to use. You can pin this to a specific version like "v2.1.0"
IMMICH_VERSION=v2

# Connection secret for postgres. You should change it to a random password
# Please use only the characters \`A-Za-z0-9\`, without special characters or spaces
DB_PASSWORD=postgres

# The values below this line do not need to be changed
###################################################################################
DB_USERNAME=postgres
DB_DATABASE_NAME=immich

LDAP_URL= ldap://openldap:1389
LDAP_BIND_DN=cn=admin,dc=example,dc=org
LDAP_BIND_PASSWORD=$LDAP_ADMIN_PASSWORD
LDAP_BASE_DN=dc=example,dc=org
LDAP_USER_BASE_DN=ou=users,dc=example,dc=org
LDAP_USER_FILTER=(objectClass=inetOrgPerson)
LDAP_ADMIN_GROUP=admins
LDAP_EMAIL_ATTRIBUTE=mail
LDAP_NAME_ATTRIBUTE=cn
LDAP_PASSWORD_ATTRIBUTE=userPassword
EOF

echo "✅ Fichier .env créé."

# 5. Lancer les services Immich en mode production
echo "🚀 Lancement de rPictures avec Docker Compose..."
sudo docker compose -f docker-compose.yml up -d

# 6. Attente du démarrage du service (optionnel : tester avec un port ouvert)
echo "⏳ Attente du démarrage de rPictures (port 3013)..."
until curl -s http://localhost:3013 > /dev/null; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ rPictures est lancé."
echo "ℹ️ Note: La synchronisation LDAP se fera après la création du premier utilisateur."

echo ""
echo "-----------------------------------------------------"
echo "Étape 13: Installation de Ryvie rTransfer"
echo "-----------------------------------------------------"

# Aller dans le dossier de travail /data/apps
cd "$APPS_DIR" || { echo "❌ Impossible d'accéder à $APPS_DIR"; exit 1; }

# 1. Cloner le dépôt si pas déjà présent
if [ -d "Ryvie-rTransfer" ]; then
    echo "✅ Le dépôt Ryvie-rTransfer existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rTransfer..."
    sudo -H -u "$EXEC_USER" git clone https://github.com/maisonnavejul/Ryvie-rTransfer.git || { echo "❌ Échec du clonage"; exit 1; }
fi

# 2. Se placer dans le dossier Ryvie-rTransfer
cd "Ryvie-rTransfer" || { echo "❌ Impossible d'accéder à Ryvie-rTransfer"; exit 1; }
pwd

# 3. Lancer rTransfer avec docker-compose.yml
echo "🚀 Lancement de Ryvie rTransfer avec docker-compose.yml..."
sudo docker compose -f docker-compose.yml up -d

# 4. Vérification du démarrage sur le port 3000
echo "⏳ Attente du démarrage de rTransfer (port 3011)..."
until curl -s http://localhost:3011 > /dev/null; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ rTransfer est lancé et prêt avec l'authentification LDAP."


echo ""
echo "-----------------------------------------------------"
echo "Étape 14: Installation de Ryvie rDrop"
echo "-----------------------------------------------------"

cd "$APPS_DIR"

if [ -d "Ryvie-rdrop" ]; then
    echo "✅ Le dépôt Ryvie-rdrop existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rdrop..."
    sudo -H -u "$EXEC_USER" git clone https://github.com/maisonnavejul/Ryvie-rdrop.git
    if [ $? -ne 0 ]; then
        echo "❌ Échec du clonage du dépôt Ryvie-rdrop."
        exit 1
    fi
fi

cd Ryvie-rdrop/rDrop-main

echo "✅ Répertoire atteint : $(pwd)"

if [ -f docker/openssl/create.sh ]; then
    chmod +x docker/openssl/create.sh
    echo "✅ Script create.sh rendu exécutable."
else
    echo "❌ Script docker/openssl/create.sh introuvable."
    exit 1
fi

echo "📦 Suppression des conteneurs orphelins..."
sudo docker compose down --remove-orphans
sudo docker compose up -d

echo ""
echo "-----------------------------------------------------"
echo "Étape 15: Installation et préparation de Rclone"
echo "-----------------------------------------------------"

# Installer unzip si nécessaire
if ! command -v unzip &> /dev/null; then
    echo "📦 Installation de unzip..."
    install_pkgs unzip
fi

# Nettoyer les installations précédentes problématiques
sudo rm -rf /usr/bin/rclone /usr/bin/rclone.new

# Télécharger et installer rclone
cd /tmp
rm -f rclone-current-linux-amd64.zip
curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip -o rclone-current-linux-amd64.zip
cd rclone-*-linux-amd64
sudo cp rclone /usr/bin/
sudo chown root:root /usr/bin/rclone
sudo chmod 755 /usr/bin/rclone
sudo mkdir -p /usr/local/share/man/man1
sudo cp rclone.1 /usr/local/share/man/man1/ 2>/dev/null || true
cd /tmp
rm -rf rclone-*-linux-amd64*

# Vérifier l'installation
RBIN="$(command -v rclone || true)"
if [ -z "$RBIN" ]; then
  echo "❌ rclone introuvable dans le PATH après installation"
  exit 1
fi
echo "✅ rclone trouvé: $RBIN"
rclone version || true

# Configuration centralisée
RCLONE_DIR="$CONFIG_DIR/rclone"
RCLONE_CONF="$RCLONE_DIR/rclone.conf"
sudo mkdir -p "$RCLONE_DIR"
sudo touch "$RCLONE_CONF"
sudo chown -R 1000:1000 "$RCLONE_DIR" || true
sudo chmod 700 "$RCLONE_DIR" || true
sudo chmod 600 "$RCLONE_CONF" || true

export RCLONE_CONFIG="$RCLONE_CONF"
grep -q 'RCLONE_CONFIG=' /etc/profile.d/ryvie_rclone.sh 2>/dev/null || \
  echo 'export RCLONE_CONFIG=/data/config/rclone/rclone.conf' | sudo tee /etc/profile.d/ryvie_rclone.sh >/dev/null

echo "🧪 Test rclone (host)"
rclone --config "$RCLONE_CONF" listremotes -vv 2>/dev/null || true
echo ""
echo "-----------------------------------------------------"
echo "Étape 16: Installation et lancement de Ryvie rDrive (compose unique)"
echo "-----------------------------------------------------"

# Dossier rDrive
RDRIVE_DIR="$APPS_DIR/Ryvie-rDrive/tdrive"

# 1) Vérifier la présence du compose et du .env
cd "$RDRIVE_DIR" || { echo "❌ Impossible d'accéder à $RDRIVE_DIR"; exit 1; }

if [ ! -f docker-compose.yml ]; then
  echo "❌ docker-compose.yml introuvable dans $RDRIVE_DIR"
  echo "   Place le fichier docker-compose.yml ici puis relance."
  exit 1
fi

# Le .env front/back est généré plus haut (NetBird → generate_env_file)
if [ ! -f "$CONFIG_DIR/rdrive/.env" ]; then
  echo "⚠️ /data/config/rdrive/.env introuvable — tentative de régénération…"
  generate_env_file || {
    echo "❌ Impossible de générer /data/config/rdrive/.env"
    exit 1
  }
fi

# 2) Lancement unique
echo "🚀 Démarrage de la stack rDrive…"
sudo docker compose --env-file "$CONFIG_DIR/rdrive/.env" pull || true
sudo docker compose --env-file "$CONFIG_DIR/rdrive/.env" up -d --build

echo ""
echo "🧪 Test rclone (container app-rdrive-node)"
if command -v docker >/dev/null 2>&1 && sudo docker ps --format '{{.Names}}' | grep -q '^app-rdrive-node$'; then
  sudo docker exec -it app-rdrive-node sh -lc '/usr/bin/rclone version && /usr/bin/rclone --config /root/.config/rclone/rclone.conf listremotes -vv' || true
else
  echo "ℹ️ Container app-rdrive-node non démarré (test container ignoré)"
fi

# 3) Attentes/health (best-effort)
echo "⏳ Attente des services (mongo, onlyoffice, node, frontend)…"
wait_for_service() {
  local svc="$1"
  local retries=60
  while [ $retries -gt 0 ]; do
    if sudo docker compose ps --format json | jq -e ".[] | select(.Service==\"$svc\") | .State==\"running\"" >/dev/null 2>&1; then
      # si health est défini, essaye de lire
      if sudo docker inspect --format='{{json .State.Health}}' "$(sudo docker compose ps -q "$svc")" 2>/dev/null | jq -e '.Status=="healthy"' >/dev/null 2>&1; then
        echo "✅ $svc healthy"
        return 0
      fi
      # sinon, running suffit
      echo "✅ $svc en cours d'exécution"
      return 0
    fi
    sleep 2
    retries=$((retries-1))
  done
  echo "⚠️ Timeout d'attente pour $svc"
  return 1
}


echo "✅ rDrive est lancé via docker-compose unique."
echo "   Frontend accessible (par défaut) sur http://localhost:3010"

echo ""
echo "======================================================"
echo "🧪 Tests de permissions (optionnel)"
echo "======================================================"
echo ""
echo "Pour vérifier que les permissions sont correctes, exécutez :"
echo ""
echo "# Tests d'écriture dans les dossiers host (doivent réussir)"
echo "sudo -u $EXEC_USER bash -lc 'touch /data/apps/.write_test && rm /data/apps/.write_test'"
echo "sudo -u $EXEC_USER bash -lc 'touch /data/config/.write_test && rm /data/config/.write_test'"
echo "sudo -u $EXEC_USER bash -lc 'touch /data/logs/.write_test && rm /data/logs/.write_test'"
echo "sudo -u $EXEC_USER bash -lc 'touch /opt/Ryvie/.write_test && rm /opt/Ryvie/.write_test'"
echo ""
echo "# Vérifier l'ownership des volumes Docker (NE PAS modifier)"
echo "ls -ld /data/docker/volumes/immich-prod_prometheus-data/_data 2>/dev/null || echo 'Volume Prometheus non trouvé'"
echo "ls -ld /data/docker/volumes/app-rpictures_pgvecto-rs/_data 2>/dev/null || echo 'Volume PostgreSQL non trouvé'"
echo ""
echo "======================================================"
echo "✅ Installation Ryvie OS terminée !"
echo "======================================================"
echo ""
echo "📍 Architecture créée :"
echo "   /opt/Ryvie/               → Application principale (Ryvie-Back, Ryvie-Front)"
echo "   /data/apps/               → Applications Ryvie (rPictures, rDrive, rdrop, rTransfer)"
echo "   /data/apps/portainer/     → Données Portainer"
echo "   /data/config/ldap/        → Configuration OpenLDAP"
echo "   /data/config/             → Configurations (netbird, rdrive, backend-view, rclone)"
echo "   /data/logs/               → Logs applicatifs"
echo "   /data/docker/             → Volumes Docker (PROTÉGÉS - ne pas modifier)"
echo ""
echo "⚠️  IMPORTANT : Si vous rencontrez des problèmes de permissions Docker,"
echo "    décommentez la ligne 'repair_docker_volumes' dans la section Docker du script"
echo "    et relancez uniquement cette partie."
echo ""

echo "newgrp docker"
sudo reboot
