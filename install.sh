#!/bin/bash

# =======================================================================
# Script d'installation Ryvie OS avec gestion d'erreurs et rollback
# Par Jules Maisonnave
# =======================================================================

set -euo pipefail  # Arrêt immédiat en cas d'erreur

# Variables globales pour le rollback
ROLLBACK_LOG="/tmp/ryvie_rollback.log"
BACKUP_DIR="/tmp/ryvie_backup_$(date +%Y%m%d_%H%M%S)"
INSTALLED_PACKAGES=()
CREATED_DIRS=()
DOCKER_CONTAINERS=()
DOCKER_IMAGES=()
MODIFIED_FILES=()

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ROLLBACK_LOG"
}

# Fonction d'erreur avec rollback automatique
error_exit() {
    local line_number=$1
    local error_code=$2
    log "❌ ERREUR: Ligne $line_number, Code d'erreur: $error_code"
    log "🔄 Début du rollback automatique..."
    perform_rollback
    exit $error_code
}

# Piège pour capturer les erreurs
trap 'error_exit ${LINENO} $?' ERR

# Fonction de sauvegarde de fichier
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        cp "$file" "$BACKUP_DIR/$file"
        MODIFIED_FILES+=("$file")
        log "💾 Sauvegarde: $file"
    fi
}

# Fonction de rollback complet
perform_rollback() {
    log "🚨 ROLLBACK EN COURS..."
    
    # Arrêter et supprimer les conteneurs Docker créés
    for container in "${DOCKER_CONTAINERS[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log "🐳 Arrêt du conteneur: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    
    # Supprimer les images Docker téléchargées
    for image in "${DOCKER_IMAGES[@]}"; do
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
            log "🐳 Suppression de l'image Docker: $image"
            docker rmi "$image" 2>/dev/null || true
        fi
    done
    
    # Supprimer les volumes Docker
    docker volume prune -f 2>/dev/null || true
    
    # Restaurer les fichiers modifiés
    for file in "${MODIFIED_FILES[@]}"; do
        if [[ -f "$BACKUP_DIR/$file" ]]; then
            cp "$BACKUP_DIR/$file" "$file"
            log "📁 Restauré: $file"
        fi
    done
    
    # Supprimer les dossiers créés (en ordre inverse)
    for ((i=${#CREATED_DIRS[@]}-1; i>=0; i--)); do
        dir="${CREATED_DIRS[i]}"
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log "🗂️ Supprimé: $dir"
        fi
    done
    
    # Supprimer les paquets installés
    for package in "${INSTALLED_PACKAGES[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            log "📦 Désinstallation: $package"
            sudo apt remove -y "$package" 2>/dev/null || true
        fi
    done
    
    # Nettoyer apt
    sudo apt autoremove -y 2>/dev/null || true
    sudo apt autoclean 2>/dev/null || true
    
    # Retirer l'utilisateur du groupe docker s'il a été ajouté
    if id -nG "$USER" | grep -qw "docker"; then
        sudo deluser "$USER" docker 2>/dev/null || true
        log "👤 Utilisateur retiré du groupe docker"
    fi
    
    # Supprimer le dossier de sauvegarde
    rm -rf "$BACKUP_DIR" 2>/dev/null || true
    
    log "✅ Rollback terminé. Toutes les modifications ont été annulées."
}

# Function de vérification de commande
check_command() {
    local cmd="$1"
    local package="$2"
    
    if ! command -v "$cmd" &> /dev/null; then
        log "📦 Installation de $package..."
        sudo apt update
        sudo apt install -y "$package"
        INSTALLED_PACKAGES+=("$package")
        
        # Vérifier que l'installation a réussi
        if ! command -v "$cmd" &> /dev/null; then
            log "❌ Échec de l'installation de $package"
            return 1
        fi
        log "✅ $package installé avec succès"
    else
        log "✅ $cmd déjà disponible"
    fi
}

# Fonction pour créer un dossier de manière sécurisée
create_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        CREATED_DIRS+=("$dir")
        log "📁 Dossier créé: $dir"
    fi
}

# Fonction pour télécharger et lancer un conteneur Docker
docker_run_container() {
    local image="$1"
    local container_name="$2"
    shift 2
    local docker_args=("$@")
    
    # Ajouter l'image à la liste pour le rollback
    DOCKER_IMAGES+=("$image")
    DOCKER_CONTAINERS+=("$container_name")
    
    # Pull de l'image
    log "🐳 Téléchargement de l'image Docker: $image"
    docker pull "$image"
    
    # Lancement du conteneur
    log "🐳 Lancement du conteneur: $container_name"
    docker run "${docker_args[@]}" --name "$container_name" "$image"
}

# =====================================================
# DÉBUT DU SCRIPT PRINCIPAL
# =====================================================

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
echo "Installation sécurisée avec rollback automatique en cas d'erreur"

# Initialisation du log
log "🚀 Début de l'installation Ryvie OS"
mkdir -p "$BACKUP_DIR"

# =====================================================
# Étape 1: Vérification des prérequis système
# =====================================================
log "----------------------------------------------------"
log "Étape 1: Vérification des prérequis système"
log "----------------------------------------------------"

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
        log "❌ Architecture non supportée: $ARCH"
        exit 1
        ;;
esac
log "✅ Architecture détectée: $ARCH ($TARGET_ARCH)"

# 2. Vérification du système d'exploitation
OS=$(uname -s)
if [[ "$OS" != "Linux" ]]; then
    log "❌ Ce script est conçu uniquement pour Linux. OS détecté: $OS"
    exit 1
fi
log "✅ Système d'exploitation: $OS"

# 3. Vérification de la mémoire physique (minimum 400 MB)
MEMORY=$(free -m | awk '/Mem:/ {print $2}')
MIN_MEMORY=400
if [[ "$MEMORY" -lt "$MIN_MEMORY" ]]; then
    log "❌ Mémoire insuffisante. ${MEMORY} MB détectés, minimum requis: ${MIN_MEMORY} MB."
    exit 1
fi
log "✅ Mémoire disponible: ${MEMORY} MB"

# 4. Vérification de l'espace disque libre sur la racine (minimum 5 GB)
FREE_DISK_KB=$(df -k / | tail -1 | awk '{print $4}')
FREE_DISK_GB=$(( FREE_DISK_KB / 1024 / 1024 ))
MIN_DISK_GB=5
if [[ "$FREE_DISK_GB" -lt "$MIN_DISK_GB" ]]; then
    log "❌ Espace disque insuffisant. ${FREE_DISK_GB} GB détectés, minimum requis: ${MIN_DISK_GB} GB."
    exit 1
fi
log "✅ Espace disque libre: ${FREE_DISK_GB} GB"

# =====================================================
# Étape 2: Installation de npm
# =====================================================
log "----------------------------------------------------"
log "Étape 2: Vérification et installation de npm"
log "----------------------------------------------------"

check_command "npm" "npm"

# =====================================================
# Étape 3: Installation de Node.js
# =====================================================
log "----------------------------------------------------"
log "Étape 3: Vérification et installation de Node.js"
log "----------------------------------------------------"

if command -v node &> /dev/null && [[ "$(node -v | cut -d 'v' -f2 | cut -d '.' -f1)" -ge 14 ]]; then
    log "✅ Node.js est déjà installé: $(node --version)"
else
    log "📦 Installation de Node.js..."
    
    # Installer 'n' si absent
    if ! command -v n &> /dev/null; then
        log "📦 Installation de 'n' (Node version manager)..."
        sudo npm install -g n
    fi
    
    # Installer Node.js stable
    sudo n stable
    
    # Corriger la session shell
    export PATH="/usr/local/bin:$PATH"
    hash -r
    
    # Vérification après installation
    if ! command -v node &> /dev/null; then
        log "❌ L'installation de Node.js a échoué"
        exit 1
    fi
    log "✅ Node.js installé: $(node --version)"
fi

# =====================================================
# Étape 4: Installation des dépendances Node.js
# =====================================================
log "----------------------------------------------------"
log "Étape 4: Installation des dépendances Node.js"
log "----------------------------------------------------"

npm install express cors socket.io dockerode diskusage systeminformation ldapjs dotenv jsonwebtoken os-utils --save

check_command "ldapsearch" "ldap-utils"

log "✅ Toutes les dépendances Node.js ont été installées"

# =====================================================
# Étape 5: Installation et vérification de Docker
# =====================================================
log "----------------------------------------------------"
log "Étape 5: Vérification et installation de Docker"
log "----------------------------------------------------"

if command -v docker &> /dev/null; then
    log "✅ Docker est déjà installé: $(docker --version)"
else
    log "📦 Installation de Docker..."
    
    # Mettre à jour les paquets
    sudo apt update
    sudo apt upgrade -y
    
    # Installer les dépendances
    sudo apt install -y ca-certificates curl gnupg lsb-release
    INSTALLED_PACKAGES+=(ca-certificates curl gnupg lsb-release)
    
    # Ajouter la clé GPG officielle de Docker
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Ajouter le dépôt Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Installer Docker Engine + Docker Compose plugin
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    INSTALLED_PACKAGES+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
fi

# Test de Docker
log "🧪 Test de Docker avec hello-world..."
sudo docker run --rm hello-world
log "✅ Docker fonctionne correctement"

# =====================================================
# Étape 6: Ajout de l'utilisateur au groupe docker
# =====================================================
log "----------------------------------------------------"
log "Étape 6: Ajout de l'utilisateur ($USER) au groupe docker"
log "----------------------------------------------------"

if ! id -nG "$USER" | grep -qw "docker"; then
    sudo usermod -aG docker "$USER"
    log "✅ Utilisateur $USER ajouté au groupe docker"
else
    log "✅ L'utilisateur $USER est déjà membre du groupe docker"
fi

# =====================================================
# Étape 7: Configuration du hostname ryvie.local
# =====================================================
log "----------------------------------------------------"
log "Étape 7: Configuration du hostname ryvie.local"
log "----------------------------------------------------"

check_command "avahi-daemon" "avahi-daemon"
check_command "avahi-browse" "avahi-utils"

# Sauvegarder et modifier la configuration avahi
backup_file "/etc/avahi/avahi-daemon.conf"
sudo sed -i 's/^#\s*host-name=.*/host-name=ryvie/' /etc/avahi/avahi-daemon.conf
sudo systemctl enable --now avahi-daemon
sudo systemctl restart avahi-daemon

log "✅ Hostname ryvie.local configuré"

# =====================================================
# Étape 8: Configuration d'OpenLDAP avec Docker Compose
# =====================================================
log "----------------------------------------------------"
log "Étape 8: Configuration d'OpenLDAP avec Docker Compose"
log "----------------------------------------------------"

# Déterminer le dossier de travail
LDAP_DIR="$HOME/Bureau"
[[ ! -d "$LDAP_DIR" ]] && LDAP_DIR="$HOME/Desktop"
[[ ! -d "$LDAP_DIR" ]] && LDAP_DIR="$HOME"

create_directory "$LDAP_DIR/ldap"
cd "$LDAP_DIR/ldap"

# Créer le fichier docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  openldap:
    image: bitnami/openldap:latest
    container_name: openldap
    environment:
      - LDAP_ADMIN_USERNAME=admin
      - LDAP_ADMIN_PASSWORD=adminpassword
      - LDAP_ROOT=dc=example,dc=org
    ports:
      - "389:1389"
      - "636:1636"
    networks:
      my_custom_network:
        ipv4_address: 172.20.0.2
    volumes:
      - openldap_data:/bitnami/openldap

volumes:
  openldap_data:

networks:
  my_custom_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
EOF

# Lancer OpenLDAP
DOCKER_CONTAINERS+=("openldap")
DOCKER_IMAGES+=("bitnami/openldap:latest")

log "🐳 Lancement d'OpenLDAP..."
sudo docker compose up -d

# Attendre que le service soit prêt
log "⏳ Attente de la disponibilité d'OpenLDAP..."
local max_attempts=30
local attempt=0
until ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -b "dc=example,dc=org" >/dev/null 2>&1; do
    sleep 2
    ((attempt++))
    if [[ $attempt -gt $max_attempts ]]; then
        log "❌ Timeout: OpenLDAP n'est pas disponible après ${max_attempts} tentatives"
        exit 1
    fi
    echo -n "."
done
echo ""
log "✅ OpenLDAP est prêt"

# Configuration des utilisateurs et groupes LDAP
log "👥 Configuration des utilisateurs LDAP..."

# Créer les utilisateurs
cat > add-users.ldif << 'EOF'
dn: cn=jules,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: jules
sn: jules
uid: jules
uidNumber: 1003
gidNumber: 1003
homeDirectory: /home/jules
mail: maisonnavejul@gmail.com
userPassword: julespassword
employeeType: admins

dn: cn=Test,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Test
sn: Test
uid: test
uidNumber: 1004
gidNumber: 1004
homeDirectory: /home/test
mail: test@gmail.com
userPassword: testpassword
employeeType: users
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f add-users.ldif

# Créer les groupes
cat > add-groups.ldif << 'EOF'
dn: cn=admins,ou=users,dc=example,dc=org
objectClass: groupOfNames
cn: admins
member: cn=jules,ou=users,dc=example,dc=org

dn: cn=users,ou=users,dc=example,dc=org
objectClass: groupOfNames
cn: users
member: cn=Test,ou=users,dc=example,dc=org
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f add-groups.ldif

# Créer l'utilisateur read-only
cat > read-only-user.ldif << 'EOF'
dn: cn=read-only,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
cn: read-only
sn: Read
uid: read-only
userPassword: readpassword
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f read-only-user.ldif

log "✅ Configuration LDAP terminée"

# =====================================================
# Étape 9: Installation de Ryvie rPictures
# =====================================================
log "----------------------------------------------------"
log "Étape 9: Installation de Ryvie rPictures"
log "----------------------------------------------------"

WORKDIR="$HOME/Bureau"
[[ ! -d "$WORKDIR" ]] && WORKDIR="$HOME/Desktop"
[[ ! -d "$WORKDIR" ]] && WORKDIR="$HOME"

cd "$WORKDIR"

if [[ ! -d "Ryvie-rPictures" ]]; then
    log "📥 Clonage du dépôt Ryvie-rPictures..."
    git clone https://github.com/maisonnavejul/Ryvie-rPictures.git
    CREATED_DIRS+=("$WORKDIR/Ryvie-rPictures")
fi

cd Ryvie-rPictures/docker

# Créer le fichier .env
cat > .env << 'EOF'
UPLOAD_LOCATION=./library
DB_DATA_LOCATION=./postgres
IMMICH_VERSION=release
DB_PASSWORD=postgres
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

# Lancer rPictures
log "🚀 Lancement de rPictures..."
sudo docker compose -f docker-compose.ryvie.yml up -d

# Attendre le démarrage
log "⏳ Attente du démarrage de rPictures..."
local max_attempts=30
local attempt=0
until curl -s http://localhost:2283 > /dev/null; do
    sleep 2
    ((attempt++))
    if [[ $attempt -gt $max_attempts ]]; then
        log "❌ Timeout: rPictures n'est pas disponible"
        exit 1
    fi
    echo -n "."
done
echo ""
log "✅ rPictures est lancé"

# =====================================================
# Étape 10: Installation de Ryvie rTransfer
# =====================================================
log "----------------------------------------------------"
log "Étape 10: Installation de Ryvie rTransfer"
log "----------------------------------------------------"

cd "$WORKDIR"

if [[ ! -d "Ryvie-rTransfer" ]]; then
    log "📥 Clonage du dépôt Ryvie-rTransfer..."
    git clone https://github.com/maisonnavejul/Ryvie-rTransfer.git
    CREATED_DIRS+=("$WORKDIR/Ryvie-rTransfer")
fi

cd Ryvie-rTransfer

# Sauvegarder et modifier la configuration
backup_file "config.yaml"
sed -i '/^ldap:/,/^[^ ]/c\
ldap:\n\
  enabled: "true"\n\
  url: ldap://172.20.0.1:389\n\
  bindDn: cn=admin,dc=example,dc=org\n\
  bindPassword: adminpassword\n\
  searchBase: ou=users,dc=example,dc=org\n\
  searchQuery: (uid=%username%)\n\
  adminGroups: admins\n\
  fieldNameMemberOf: employeeType\n\
  fieldNameEmail: mail' config.yaml

# Lancer rTransfer
log "🚀 Lancement de rTransfer..."
sudo docker compose -f docker-compose.local.yml up -d

# Attendre le démarrage
log "⏳ Attente du démarrage de rTransfer..."
local max_attempts=30
local attempt=0
until curl -s http://localhost:3000 > /dev/null; do
    sleep 2
    ((attempt++))
    if [[ $attempt -gt $max_attempts ]]; then
        log "❌ Timeout: rTransfer n'est pas disponible"
        exit 1
    fi
    echo -n "."
done
echo ""
log "✅ rTransfer est lancé"

# =====================================================
# Étape 11: Installation de Ryvie rDrop
# =====================================================
log "----------------------------------------------------"
log "Étape 11: Installation de Ryvie rDrop"
log "----------------------------------------------------"

cd "$WORKDIR"

if [[ ! -d "Ryvie-rdrop" ]]; then
    log "📥 Clonage du dépôt Ryvie-rdrop..."
    git clone https://github.com/maisonnavejul/Ryvie-rdrop.git
    CREATED_DIRS+=("$WORKDIR/Ryvie-rdrop")
fi

cd Ryvie-rdrop/snapdrop-master/snapdrop-master

chmod +x docker/openssl/create.sh
docker compose up -d

log "✅ rDrop est lancé"

# =====================================================
# Étape 12: Installation VPN (optionnelle)
# =====================================================
log "----------------------------------------------------"
log "Étape 12: Installation VPN NetBird (optionnelle)"
log "----------------------------------------------------"

echo "Pour permettre l'accès distant sécurisé à votre serveur Ryvie,"
echo "nous proposons d'installer automatiquement un VPN."
echo ""
read -p "Souhaitez-vous installer le VPN NetBird ? (O/N) : " choix

if [[ "$choix" == "O" || "$choix" == "o" ]]; then
    log "📦 Installation du VPN NetBird..."
    curl -fsSL https://pkgs.netbird.io/install.sh | sh
    netbird up --management-url https://jules.test.ryvie.fr --admin-url https://jules.test.ryvie.fr --setup-key DB1A3E54-0FC1-4A9E-BBCD-31C75A25866E
    log "✅ VPN installé et configuré"
else
    log "⏭️ Installation du VPN ignorée"
fi

# =====================================================
# Étape 13: Installation et lancement du Back-End
# =====================================================
log "----------------------------------------------------"
log "Étape 13: Installation et lancement du Back-End"
log "----------------------------------------------------"

cd "$WORKDIR"

if [[ ! -d "Ryvie" ]]; then
    log "📥 Clonage du dépôt Ryvie Backend..."
    git clone https://github.com/maisonnavejul/Ryvie.git
    CREATED_DIRS+=("$WORKDIR/Ryvie")
fi

cd Ryvie
git switch Back-End
cd Ryvie-Back

log "🚀 Lancement du serveur Backend..."
# Note: Cette commande va bloquer, donc on la lance en arrière-plan
nohup node index.js > backend.log 2>&1 &
BACKEND_PID=$!

# Attendre quelques secondes pour vérifier que le backend démarre
sleep 5
if ! kill -0 $BACKEND_PID 2>/dev/null; then
    log "❌ Le backend a échoué au démarrage"
    exit 1
fi

log "✅ Backend lancé avec PID: $BACKEND_PID"

# =====================================================
# INSTALLATION TERMINÉE AVEC SUCCÈS
# =====================================================
log "🎉🎉🎉 INSTALLATION RYVIE OS TERMINÉE AVEC SUCCÈS ! 🎉🎉🎉"
log ""
log "📋 Résumé des services lancés:"
log "   • OpenLDAP: http://localhost:389"
log "   • rPictures: http://localhost:2283"
log "   • rTransfer: http://localhost:3000"
log "   • rDrop: Vérifiez la configuration Docker"
log "   • Backend API: En cours d'exécution (PID: $BACKEND_PID)"
log ""
log "⚠️  IMPORTANT: Redémarrez votre session pour appliquer les droits Docker"
log "💡 Utilisez 'newgrp docker' ou reconnectez-vous"
log ""
log "📁 Logs d'installation: $ROLLBACK_LOG"
log "💾 Sauvegarde des fichiers: $BACKUP_DIR"

# Nettoyage du dossier de sauvegarde (optionnel)
# rm -rf "$BACKUP_DIR"

echo ""
echo "🔄 Application des droits Docker pour la session actuelle..."
newgrp docker
