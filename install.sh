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

MARKER_FILE="$HOME/.ryvie_docker_group_done"

if id -nG "$USER" | grep -qw "docker"; then
    echo "✅ L'utilisateur $USER est déjà membre du groupe docker."
else
    echo "➕ Ajout de $USER au groupe docker..."
    sudo usermod -aG docker "$USER"

    echo "♻️ Redémarrage du shell avec le groupe docker actif..."
    echo "⚠️ Vous allez peut-être devoir entrer votre mot de passe à nouveau."

    # Marque le script comme déjà passé par ici
    touch "$MARKER_FILE"
    exec newgrp docker
fi

# On vérifie si c'est bien la relance
if [ -f "$MARKER_FILE" ]; then
    echo "✅ Relance réussie avec le groupe docker actif."
    rm "$MARKER_FILE"
fi

echo "-----------------------------------------------------"
echo "Etape 9: Ip du cloud Ryvie ryvie.local"
echo "-----------------------------------------------------"
echo " ( à implémenter )"
echo ""

echo "-----------------------------------------------------"
echo "Etape 10: Configuration d'OpenLDAP avec Docker Compose"
echo "-----------------------------------------------------"
echo " ( à implémenter, non inclus car mot de passe à gérer )"


