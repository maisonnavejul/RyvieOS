#!/bin/bash
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

# helper: retourne Desktop/Bureau ou HOME si introuvable
get_desktop_dir() {
    local d="$HOME/Bureau"
    if [ ! -d "$d" ]; then
        d="$HOME/Desktop"
    fi
    if [ ! -d "$d" ]; then
        d="$HOME"
    fi
    printf '%s' "$d"
}

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
REPOS=(
    "Ryvie-rPictures"
    "Ryvie-rTransfer"
    "Ryvie-rdrop"
    "Ryvie-rDrive"
    "Ryvie"
)


# Demander la branche à cloner
read -p "Quelle branche veux-tu cloner ? " BRANCH
if [[ -z "$BRANCH" ]]; then
    echo "❌ Branche invalide. Annulation."
    exit 1
fi

# Fonction de vérification des identifiants
verify_credentials() {
    local user="$1"
    local token="$2"
    local status_code

    status_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$token" https://api.github.com/user)
    [[ "$status_code" == "200" ]]
}

# Demander les identifiants GitHub s'ils ne sont pas valides
while true; do
    if [[ -z "$GITHUB_USER" ]]; then
        read -p "Entrez votre nom d'utilisateur GitHub : " GITHUB_USER
    fi

    if [[ -z "$GITHUB_TOKEN" ]]; then
        read -s -p "Entrez votre token GitHub personnel : " GITHUB_TOKEN
        echo
    fi

    if verify_credentials "$GITHUB_USER" "$GITHUB_TOKEN"; then
        echo "✅ Authentification GitHub réussie."
        break
    else
        echo "❌ Authentification échouée. Veuillez réessayer."
        unset GITHUB_USER
        unset GITHUB_TOKEN
    fi
done

# Déterminer le répertoire de travail de façon robuste (Bureau/Desktop/Home)
WORKDIR="$(get_desktop_dir)"
cd "$WORKDIR" || { echo "❌ Impossible d'accéder à $WORKDIR"; exit 1; }

CREATED_DIRS=()

log() {
    echo -e "$1"
}
OWNER="maisonnavejul"
# Clonage des dépôts
for repo in "${REPOS[@]}"; do
    if [[ ! -d "$repo" ]]; then
        repo_url="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${OWNER}/${repo}.git"
        log "📥 Clonage du dépôt $repo (branche $BRANCH)..."
        git clone --branch "$BRANCH" "$repo_url" "$repo"
        if [[ $? -eq 0 ]]; then
            CREATED_DIRS+=("$WORKDIR/$repo")
        else
            log "❌ Échec du clonage du dépôt : $repo"
        fi
    else
        log "✅ Dépôt déjà cloné: $repo"
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


echo ""
echo "------------------------------------------"
echo " Étape 5 : Vérification et installation de Node.js "
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
echo "Etape 6: Vérification des dépendances (mode strict pour cette section)"
echo "----------------------------------------------------"
# Activer le comportement "exit on error" uniquement pour l'installation des dépendances
strict_enter
# Installer les dépendances Node.js
#npm install express cors http socket.io os dockerode ldapjs
npm install express cors socket.io dockerode diskusage systeminformation ldapjs dotenv jsonwebtoken os-utils --save
install_pkgs ldap-utils
# Vérifier le code de retour de npm install (strict mode assure l'arrêt si npm install échoue)
echo ""
echo "Tous les modules ont été installés avec succès."
strict_exit

# =====================================================
# Étape 7: Vérification de Docker et installation si nécessaire
# =====================================================
echo "----------------------------------------------------"
echo "Étape 7: Vérification de Docker (mode strict pour cette section)"
echo "----------------------------------------------------"
# Activer strict mode uniquement pour la section Docker
strict_enter
if command -v docker > /dev/null 2>&1; then
    echo "Docker est déjà installé : $(docker --version)"
    echo "Vérification de Docker en exécutant 'docker run hello-world'..."
    sudo docker run hello-world
    if [ $? -eq 0 ]; then
        echo "Docker fonctionne correctement."
    else
        echo "Erreur: Docker a rencontré un problème lors de l'exécution du test."
    fi
else
    echo "Docker n'est pas installé. L'installation va débuter..."

    ### 🐳 1. Mettre à jour les paquets
    $APT_CMD update
    $APT_CMD upgrade -y

    ### 🐳 2. Installer les dépendances nécessaires
    install_pkgs ca-certificates curl gnupg lsb-release

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
        # Fallback: installer via le script officiel (get.docker.com)
        if curl -fsSL https://get.docker.com | sudo sh; then
            echo "✅ Docker installé via get.docker.com"
        else
            echo "❌ Échec de l'installation de Docker via apt et get.docker.com. Continuer sans Docker."
        fi
    fi

    ### ✅ 6. Vérifier que Docker fonctionne
    if command -v docker > /dev/null 2>&1; then
        echo "Vérification de Docker en exécutant 'docker run hello-world'..."
        sudo docker run --rm hello-world || echo "⚠️ 'docker run hello-world' a échoué."
        echo "Docker a été installé et fonctionne (ou tenté)."
    else
        echo "Erreur lors de l'installation ou de la vérification de Docker. Docker absent."
    fi
fi
strict_exit

echo ""
echo "----------------------------------------------------"
echo "Étape 8: Installation de Redis"
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
 echo "Etape 9: Ajout de l'utilisateur ($USER) au groupe docker "
 echo "--------------------------------------------------"
 echo ""
 
 # Vérifier si docker est disponible avant d'ajouter l'utilisateur au groupe
 if command -v docker > /dev/null 2>&1; then
     # Créer le groupe docker si nécessaire
     if ! getent group docker > /dev/null 2>&1; then
         sudo groupadd docker || true
     fi

     if id -nG "$USER" | grep -qw "docker"; then
         echo "L'utilisateur $USER est déjà membre du groupe docker."
     else
         sudo usermod -aG docker "$USER"
         echo "L'utilisateur $USER a été ajouté au groupe docker."
         echo "Veuillez redémarrer votre session pour appliquer définitivement les changements."
     fi
 else
     echo "⚠️ Docker n'est pas installé — saut de l'ajout de l'utilisateur au groupe docker."
 fi

  echo "-----------------------------------------------------"
  echo "Etape 10: Installation et démarrage de Portainer"
  echo "-----------------------------------------------------"
  
# Si Docker absent, sauter Portainer
if command -v docker > /dev/null 2>&1; then
  # Créer le volume Portainer s'il n'existe pas
  if ! sudo docker volume ls -q | grep -q '^portainer_data$'; then
    sudo docker volume create portainer_data
  fi
  
  # Lancer Portainer uniquement s'il n'existe pas déjà
  if ! sudo docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then
    sudo docker run -d \
      --name portainer \
      --restart=always \
      -p 8000:8000 \
      -p 9443:9443 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
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
  echo "Etape 11: Ip du cloud Ryvie ryvie.local"
  echo "-----------------------------------------------------"

# Installer avahi via la fonction d'installation (compatible Debian)
install_pkgs avahi-daemon avahi-utils || true
sudo systemctl enable --now avahi-daemon
sudo sed -i 's/^#\s*host-name=.*/host-name=ryvie/' /etc/avahi/avahi-daemon.conf || true
sudo systemctl restart avahi-daemon || true

echo ""
echo "Etape 12: Configuration d'OpenLDAP avec Docker Compose"
echo "-----------------------------------------------------"

# 1. Créer le dossier ldap sur Desktop/Bureau/Home et s'y positionner
LDAP_DIR="$(get_desktop_dir)"
sudo docker network prune -f
mkdir -p "$LDAP_DIR/ldap"
cd "$LDAP_DIR/ldap"

# 2. Créer le fichier docker-compose.yml pour lancer OpenLDAP
cat <<'EOF' > docker-compose.yml
version: '3.8'

services:
  openldap:
    image: bitnami/openldap:latest
    container_name: openldap
    environment:
      - LDAP_ADMIN_USERNAME=admin           # Nom d'utilisateur admin LDAP
      - LDAP_ADMIN_PASSWORD=adminpassword   # Mot de passe admin
      - LDAP_ROOT=dc=example,dc=org         # Domaine racine de l'annuaire
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
echo "Attente de la disponibilité du service OpenLDAP..."
until ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -b "dc=example,dc=org" >/dev/null 2>&1; do
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

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f delete-entries.ldif

# 6. Créer les utilisateurs via add-users.ldif
cat <<'EOF' > add-users.ldif
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

# 7. Tester l'accès de l'utilisateur "Test"
ldapwhoami -x -H ldap://localhost:389 -D "cn=Test,ou=users,dc=example,dc=org" -w testpassword

# 8. Créer les groupes via add-groups.ldif
cat <<'EOF' > add-groups.ldif
# Groupe admins
dn: cn=admins,ou=users,dc=example,dc=org
objectClass: groupOfNames
cn: admins
member: cn=jules,ou=users,dc=example,dc=org

# Groupe users
dn: cn=users,ou=users,dc=example,dc=org
objectClass: groupOfNames
cn: users
member: cn=Test,ou=users,dc=example,dc=org
EOF

ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f add-groups.ldif

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
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword -f read-only-user.ldif

echo "Copie du fichier ACL read-only dans le conteneur OpenLDAP..."
sudo docker cp acl-read-only.ldif openldap:/tmp/acl-read-only.ldif

echo "Application de la configuration ACL read-only..."
sudo docker exec -it openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl-read-only.ldif

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

echo "✅ Configuration ACL pour le groupe admins appliquée."

 echo " ( à implémenter non mis car mdp dedans )"
echo ""
echo "-----------------------------------------------------"
echo "Étape 11: Installation de Ryvie rPictures et synchronisation LDAP"
echo "-----------------------------------------------------"
# 1. Aller sur le Bureau ou Desktop (WORKDIR déjà initialisé plus haut)
echo "📁 Dossier sélectionné : $WORKDIR"
cd "$WORKDIR" || { echo "❌ Impossible d'accéder à $WORKDIR"; exit 1; }

# 2. Cloner le dépôt si pas déjà présent
if [ -d "Ryvie-rPictures" ]; then
    echo "✅ Le dépôt Ryvie-rPictures existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rPictures..."
    git clone https://github.com/maisonnavejul/Ryvie-rPictures.git
    if [ $? -ne 0 ]; then
        echo "❌ Échec du clonage du dépôt. Arrêt du script."
        exit 1
    fi
fi


# 3. Se placer dans le dossier docker
cd Ryvie-rPictures/docker

# 4. Créer le fichier .env avec les variables nécessaires
echo "📝 Création du fichier .env..."

cat <<EOF > .env
# The location where your uploaded files are stored
UPLOAD_LOCATION=./library

# The location where your database files are stored
DB_DATA_LOCATION=./postgres

# Timezone
# TZ=Etc/UTC

# Immich version
IMMICH_VERSION=release

# Postgres password (change it in prod)
DB_PASSWORD=postgres

# Internal DB vars
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

echo "✅ Fichier .env créé."

# 5. Lancer les services Immich en mode production
echo "🚀 Lancement de Immich (rPictures) avec Docker Compose..."
sudo docker compose -f docker-compose.ryvie.yml up -d

# 6. Attente du démarrage du service (optionnel : tester avec un port ouvert)
echo "⏳ Attente du démarrage d'Immich (port 2283)..."
until curl -s http://localhost:2283 > /dev/null; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ rPictures est lancé."

# 7. Synchroniser les utilisateurs LDAP
echo "🔁 Synchronisation des utilisateurs LDAP avec Immich..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X GET http://localhost:2283/api/admin/users/sync-ldap)

if [ "$RESPONSE" -eq 200 ]; then
    echo "✅ Synchronisation LDAP réussie avec rPictures."
else
    echo "❌ Échec de la synchronisation LDAP (code HTTP : $RESPONSE)"
fi
echo ""
echo "-----------------------------------------------------"
echo "Étape 12: Installation de Ryvie rTransfer et synchronisation LDAP"
echo "-----------------------------------------------------"

# Aller dans le dossier Desktop/Bureau/Home (fallback centralisé)
BASE_DIR="$(get_desktop_dir)"
cd "$BASE_DIR" || { echo "❌ Impossible d'accéder à $BASE_DIR"; exit 1; }

# 1. Cloner le dépôt si pas déjà présent
if [ -d "Ryvie-rTransfer" ]; then
    echo "✅ Le dépôt Ryvie-rTransfer existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rTransfer..."
    git clone https://github.com/maisonnavejul/Ryvie-rTransfer.git || { echo "❌ Échec du clonage"; exit 1; }
fi

# 2. Se placer dans le dossier Ryvie-rTransfer
cd "Ryvie-rTransfer" || { echo "❌ Impossible d'accéder à Ryvie-rTransfer"; exit 1; }
pwd

# 3. Lancer rTransfer avec docker-compose.local.yml
echo "🚀 Lancement de Ryvie rTransfer avec docker-compose.local.yml..."
sudo docker compose -f docker-compose.local.yml up -d

# 4. Vérification du démarrage sur le port 3000
echo "⏳ Attente du démarrage de rTransfer (port 3000)..."
until curl -s http://localhost:3011 > /dev/null; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ rTransfer est lancé et prêt avec l’authentification LDAP."


echo ""
echo "-----------------------------------------------------"
echo "-----------------------------------------------------"
echo "Étape 13: Installation de Ryvie rDrop"
echo "-----------------------------------------------------"

cd "$WORKDIR"

if [ -d "Ryvie-rdrop" ]; then
    echo "✅ Le dépôt Ryvie-rdrop existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rdrop..."
    git clone https://github.com/maisonnavejul/Ryvie-rdrop.git
    if [ $? -ne 0 ]; then
        echo "❌ Échec du clonage du dépôt Ryvie-rdrop."
        exit 1
    fi
fi

cd Ryvie-rdrop/snapdrop-master/snapdrop-master

echo "✅ Répertoire atteint : $(pwd)"

if [ -f docker/openssl/create.sh ]; then
    chmod +x docker/openssl/create.sh
    echo "✅ Script create.sh rendu exécutable."
else
    echo "❌ Script docker/openssl/create.sh introuvable."
    exit 1
fi

echo "📦 Suppression des conteneurs orphelins et anciens réseaux..."
sudo docker compose down --remove-orphans
sudo docker network prune -f
sudo docker compose up -d

echo ""
echo "-----------------------------------------------------"
echo "Étape 14: Installation et préparation de Rclone"
echo "-----------------------------------------------------"

# Installer/mettre à jour Rclone (méthode officielle)
# (réexécutable sans risque : met à jour si déjà installé)
curl -fsSL https://rclone.org/install.sh | sudo bash

# Vérifie qu’il est bien là :
# - essaie /usr/bin/rclone comme demandé
# - sinon affiche l’emplacement réel retourné par command -v
command -v rclone && ls -l /usr/bin/rclone || {
  echo "ℹ️ rclone n'est pas sous /usr/bin, emplacement détecté :"
  command -v rclone
  ls -l "$(command -v rclone)" 2>/dev/null || true
}

# Version pour confirmation
rclone version || true

# Préparation du fichier de config (root)
sudo mkdir -p /root/.config/rclone
sudo touch /root/.config/rclone/rclone.conf

# Permissions strictes
sudo chown -R root:root /root/.config/rclone
sudo chmod 700 /root/.config/rclone
sudo chmod 600 /root/.config/rclone/rclone.conf

# Vérification du chemin utilisé par rclone (root)
sudo rclone config file

echo ""
echo "-----------------------------------------------------"
echo "Étape 15: Installation et lancement de Ryvie rDrive"
echo "-----------------------------------------------------"

# Sécurités
# (removed duplicate `set -euo pipefail` here; strict mode already enabled above)
# Dossier du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Déduction robuste du chemin de tdrive
if [ -d "$SCRIPT_DIR/Ryvie-rDrive/tdrive" ]; then
  RDRIVE_DIR="$SCRIPT_DIR/Ryvie-rDrive/tdrive"
elif [ -d "$SCRIPT_DIR/tdrive" ]; then
  # cas où le script est lancé depuis le repo Ryvie-rDrive
  RDRIVE_DIR="$SCRIPT_DIR/tdrive"
elif [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR/Ryvie-rDrive/tdrive" ]; then
  RDRIVE_DIR="$WORKDIR/Ryvie-rDrive/tdrive"
else
  echo "❌ Impossible de trouver le dossier 'tdrive' (cherché depuis $SCRIPT_DIR et \$WORKDIR)."
  exit 1
fi

cd "$RDRIVE_DIR"

# --- NEW: wrapper Docker (utilise sudo si nécessaire) + start du service ---
if docker info >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi
d() { $DOCKER "$@" ; }
dc() { $DOCKER compose "$@" ; }
# Assure que le daemon tourne (silencieux si déjà actif)
sudo systemctl start docker 2>/dev/null || true

# Fonction utilitaire pour attendre un conteneur Docker
wait_cid() {
  local cid="$1"
  local name state health
  name="$(d inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
  echo "⏳ Attente du conteneur $name ..."
  while :; do
    state="$(d inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo 'unknown')"
    health="$(d inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    if [[ "$state" == "running" && ( -z "$health" || "$health" == "healthy" ) ]]; then
      echo "✅ $name prêt."
      break
    fi
    sleep 2
    echo "   …"
  done
}

# 1. Lancer OnlyOffice
echo "🔹 Démarrage de OnlyOffice..."
dc -f docker-compose.dev.onlyoffice.yml \
   -f docker-compose.onlyoffice-connector-override.yml \
   up -d

# 1b. Attendre que tous les conteneurs OnlyOffice soient prêts
OO_CIDS=$(dc -f docker-compose.dev.onlyoffice.yml \
             -f docker-compose.onlyoffice-connector-override.yml \
             ps -q)

if [ -z "$OO_CIDS" ]; then
  echo "❌ Aucun conteneur détecté pour la stack OnlyOffice."
  exit 1
fi

for cid in $OO_CIDS; do
  wait_cid "$cid"
done

# 2. Build et démarrage du service node
echo "🔹 Build du service node..."
dc -f docker-compose.minimal.yml build node

echo "🔹 Démarrage du service node..."
dc -f docker-compose.minimal.yml up -d node

# 2b. Attendre que node soit prêt
NODE_CID=$(dc -f docker-compose.minimal.yml ps -q node)
wait_cid "$NODE_CID"

# 3. Lancer frontend
echo "🔹 Démarrage du service frontend..."
dc -f docker-compose.minimal.yml up -d frontend

# 4. Démarrer le reste du minimal
echo "🔹 Démarrage du reste des services (mongo, etc.)..."
dc -f docker-compose.minimal.yml up -d

echo "✅ rDrive est lancé."


echo "-----------------------------------------------------"
echo "Étape 16: Installation et lancement du Back-end-view"
echo "-----------------------------------------------------"

# S'assurer d'être dans le répertoire de travail
cd "$WORKDIR" || { echo "❌ WORKDIR introuvable: $WORKDIR"; exit 1; }

# Vérifier la présence du dépôt Ryvie
if [ ! -d "Ryvie" ]; then
    echo "❌ Le dépôt 'Ryvie' est introuvable dans $WORKDIR. Assurez-vous qu'il a été cloné plus haut."
    exit 1
fi

# Aller dans le dossier Back-end-view
cd "Ryvie/Back-end-view" || { echo "❌ Dossier 'Ryvie/Back-end-view' introuvable"; exit 1; }

# Copier le fichier .env depuis Desktop (fallback Bureau)
SRC_ENV="$HOME/Desktop/.env"
if [ ! -f "$SRC_ENV" ]; then
  ALT_ENV="$HOME/Bureau/.env"
  if [ -f "$ALT_ENV" ]; then
    SRC_ENV="$ALT_ENV"
  fi
fi

if [ -f "$SRC_ENV" ]; then
  echo "📄 Copie de $SRC_ENV vers $(pwd)/.env"
  cp "$SRC_ENV" .env
else
  echo "⚠️ Aucun .env trouvé sur Desktop ou Bureau. Étape de copie ignorée."
fi

# Installer les dépendances et lancer l'application
echo "📦 Installation des dépendances (npm install)"
npm install || { echo "❌ npm install a échoué"; exit 1; }

echo "🚀 Lancement de Back-end-view (node index.js) au premier plan"
echo "ℹ️ Les logs s'affichent ci-dessous. Appuyez sur Ctrl+C pour arrêter."
mkdir -p logs
# Afficher les logs en direct ET les sauvegarder dans un fichier
node index.js 2>&1 | tee -a logs/backend-view.out


newgrp docker