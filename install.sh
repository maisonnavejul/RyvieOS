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
echo " Etape 5 Vérification et installation de Node.js "
echo "------------------------------------------"
echo ""

# Vérifier si Node.js est installé
if command -v node > /dev/null 2>&1; then
    echo "Node.js est déjà installé : $(node --version)"
else
    echo "Node.js n'est pas installé. Installation en cours..."
    sudo apt update
    sudo apt install -y nodejs
    # Vérification après installation
    if command -v node > /dev/null 2>&1; then
        echo "Node.js a été installé avec succès : $(node --version)"
    else
        echo "Erreur: L'installation de Node.js a échoué."
        exit 1
    fi
fi

echo ""
echo "------------------------------------------"
echo " Vérification et installation de npm "
echo "------------------------------------------"
echo ""

# Vérifier si npm est installé
if command -v npm > /dev/null 2>&1; then
    echo "npm est déjà installé : $(npm --version)"
else
    echo "npm n'est pas installé. Installation en cours..."
    sudo apt update
    sudo apt install -y npm
    # Vérification après installation
    if command -v npm > /dev/null 2>&1; then
        echo "npm a été installé avec succès : $(npm --version)"
    else
        echo "Erreur: L'installation de npm a échoué."
        exit 1
    fi
fi

# 6. Vérification des dépendances (place réservée)
echo "Etape 6: Vérification des dépendances: (à implémenter...)"
# Installer les dépendances Node.js
#npm install express cors http socket.io os dockerode ldapjs
sudo apt install -y ldap-utils
# Vérifier le code de retour de npm install
if [ $? -eq 0 ]; then
    echo ""
    echo "Tous les modules ont été installés avec succès."
else
    echo ""
    echo "Erreur lors de l'installation d'un ou plusieurs modules."
fi
# =====================================================
# Étape 7: Vérification de Docker et installation si nécessaire
# =====================================================
echo "----------------------------------------------------"
echo "Étape 7: Vérification de Docker"
echo "----------------------------------------------------"

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
    sudo apt update
    sudo apt upgrade -y

    ### 🐳 2. Installer les dépendances nécessaires
    sudo apt install -y ca-certificates curl gnupg lsb-release

    ### 🐳 3. Ajouter la clé GPG officielle de Docker
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    ### 🐳 4. Ajouter le dépôt Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    ### 🐳 5. Installer Docker Engine + Docker Compose plugin
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    ### ✅ 6. Vérifier que Docker fonctionne
    echo "Vérification de Docker en exécutant 'docker run hello-world'..."
    sudo docker run hello-world
    if [ $? -eq 0 ]; then
        echo "Docker a été installé et fonctionne correctement."
    else
        echo "Erreur lors de l'installation ou de la vérification de Docker."
    fi
fi
echo ""
 echo "--------------------------------------------------"
 echo "Etape 8: Ajout de l'utilisateur ($USER) au groupe docker "
 echo "--------------------------------------------------"
 echo ""
 
 # Vérifier si l'utilisateur est déjà dans le groupe docker
 if id -nG "$USER" | grep -qw "docker"; then
     echo "L'utilisateur $USER est déjà membre du groupe docker."
 else
     # Ajouter l'utilisateur actuel au groupe docker et appliquer la modification
     sudo usermod -aG docker $USER
     echo "L'utilisateur $USER a été ajouté au groupe docker."
     echo "Veuillez redémarrer votre session pour appliquer définitivement les changements."
 fi
 
 echo "-----------------------------------------------------"
 echo "Etape 9: Ip du cloud Ryvie ryvie.local"
 echo "-----------------------------------------------------"
sudo apt update && sudo apt install -y avahi-daemon avahi-utils && sudo systemctl enable --now avahi-daemon && sudo sed -i 's/^#\s*host-name=.*/host-name=ryvievmtest/' /etc/avahi/avahi-daemon.conf && sudo systemctl restart avahi-daemon
 echo ""
echo "Etape 10: Configuration d'OpenLDAP avec Docker Compose"
echo "-----------------------------------------------------"

# 1. Créer le dossier ldap sur le Bureau ou Desktop et s'y positionner
LDAP_DIR="$HOME/Bureau"
[ ! -d "$LDAP_DIR" ] && LDAP_DIR="$HOME/Desktop"
[ ! -d "$LDAP_DIR" ] && LDAP_DIR="$HOME"

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
description: admins

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
description: users
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

# 1. Aller sur le Bureau ou Desktop
WORKDIR="$HOME/Bureau"
[ ! -d "$WORKDIR" ] && WORKDIR="$HOME/Desktop"
[ ! -d "$WORKDIR" ] && WORKDIR="$HOME"

echo "📁 Dossier sélectionné : $WORKDIR"
cd "$WORKDIR"

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

# 1. Cloner le dépôt si pas déjà présent
cd "$WORKDIR"
if [ -d "Ryvie-rTransfer" ]; then
    echo "✅ Le dépôt Ryvie-rTransfer existe déjà."
else
    echo "📥 Clonage du dépôt Ryvie-rTransfer..."
    git clone https://github.com/maisonnavejul/Ryvie-rTransfer.git
    if [ $? -ne 0 ]; then
        echo "❌ Échec du clonage du dépôt. Arrêt du script."
        exit 1
    fi
fi

# 2. Se placer dans le dossier
cd Ryvie-rTransfer

# 3. Mise à jour de la section LDAP dans le fichier config.yaml
echo "🛠️ Mise à jour de la configuration LDAP dans config.yaml..."
sed -i '/^ldap:/,/^[^ ]/c\
ldap:\n\
  enabled: "true"\n\
  url: ldap://172.20.0.1:389\n\
  bindDn: cn=admin,dc=example,dc=org\n\
  bindPassword: adminpassword\n\
  searchBase: ou=users,dc=example,dc=org\n\
  searchQuery: (uid=%username%)\n\
  adminGroups: admins\n\
  fieldNameMemberOf: description\n\
  fieldNameEmail: mail' config.yaml

echo "✅ Bloc LDAP modifié avec succès."

# 4. Lancer rTransfer avec le fichier docker-compose.local.yml
echo "🚀 Lancement de Ryvie rTransfer avec docker-compose.local.yml..."
sudo docker compose -f docker-compose.local.yml up -d

# 5. Vérification du démarrage sur le port 3000
echo "⏳ Attente du démarrage de rTransfer (port 3000)..."
until curl -s http://localhost:3000 > /dev/null; do
    sleep 2
    echo -n "."
done
echo ""
echo "✅ rTransfer est lancé et prêt avec l’authentification LDAP."


newgrp docker
