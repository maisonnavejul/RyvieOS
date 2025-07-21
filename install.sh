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
echo ""

# Charger variables depuis .env si présent
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

GITHUB_USER=${GITHUB_USER:-"1-thegreenprogrammer"}
echo "Utilisateur GitHub utilisé : $GITHUB_USER"

echo "----------------------------------------------------"
echo "Étape 1: Vérification des prérequis système"
echo "----------------------------------------------------"

ARCH=$(uname -m)
case "$ARCH" in
    *aarch64*) TARGET_ARCH="arm64" ;;
    *64*) TARGET_ARCH="amd64" ;;
    *armv7*) TARGET_ARCH="arm-7" ;;
    *) echo "Erreur: Architecture non supportée: $ARCH"; exit 1 ;;
esac
echo "Architecture détectée: $ARCH ($TARGET_ARCH)"

OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
    echo "Erreur: Ce script est conçu uniquement pour Linux. OS détecté: $OS"
    exit 1
fi
echo "Système d'exploitation: $OS"

MEMORY=$(free -m | awk '/Mem:/ {print $2}')
MIN_MEMORY=400
if [ "$MEMORY" -lt "$MIN_MEMORY" ]; then
    echo "Erreur: Mémoire insuffisante. ${MEMORY} MB détectés, minimum requis: ${MIN_MEMORY} MB."
    exit 1
fi
echo "Mémoire disponible: ${MEMORY} MB (OK)"

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

if command -v npm > /dev/null 2>&1; then
    echo "npm est déjà installé : $(npm --version)"
else
    echo "npm n'est pas installé. Installation en cours..."
    sudo apt update
    sudo apt install -y npm
    if command -v npm > /dev/null 2>&1; then
        echo "npm a été installé avec succès : $(npm --version)"
    else
        echo "Erreur: L'installation de npm a échoué."
        exit 1
    fi
fi

echo ""
echo "------------------------------------------"
echo " Étape 5 : Vérification et installation de Node.js "
echo "------------------------------------------"
echo ""

if command -v node > /dev/null 2>&1 && [ "$(node -v | cut -d 'v' -f2 | cut -d '.' -f1)" -ge 14 ]; then
    echo "Node.js est déjà installé : $(node --version)"
else
    echo "Node.js est manquant ou trop ancien. Installation de la version stable avec 'n'..."

    if ! command -v n > /dev/null 2>&1; then
        echo "Installation de 'n' (Node version manager)..."
        sudo npm install -g n
    fi

    sudo n stable

    export PATH="/usr/local/bin:$PATH"
    hash -r

    if command -v node > /dev/null 2>&1; then
        echo "Node.js a été installé avec succès : $(node --version)"
    else
        echo "Erreur : l'installation de Node.js a échoué."
        exit 1
    fi
fi

echo "----------------------------------------------------"
echo "Etape 6: Installation des dépendances Node.js"
echo "----------------------------------------------------"
npm install express cors socket.io dockerode diskusage systeminformation ldapjs dotenv jsonwebtoken os-utils --save
sudo apt install -y ldap-utils
if [ $? -eq 0 ]; then
    echo "Tous les modules ont été installés avec succès."
else
    echo "Erreur lors de l'installation d'un ou plusieurs modules."
fi

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
    echo "Docker n'est pas installé. Installation en cours..."

    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
echo "Ajout de l'utilisateur ($USER) au groupe docker"
echo "--------------------------------------------------"

if id -nG "$USER" | grep -qw "docker"; then
    echo "L'utilisateur $USER est déjà membre du groupe docker."
else
    sudo usermod -aG docker $USER
    echo "L'utilisateur $USER a été ajouté au groupe docker."
    echo "Veuillez vous déconnecter/reconnecter ou lancer 'newgrp docker' pour appliquer les changements."
fi

echo ""
echo "-----------------------------------------------------"
echo "Étape 8 : Clonage des dépôts GitHub via SSH"
echo "-----------------------------------------------------"

WORKDIR="$HOME/Bureau"
[ ! -d "$WORKDIR" ] && WORKDIR="$HOME/Desktop"
[ ! -d "$WORKDIR" ] && WORKDIR="$HOME"

echo "Dossier de travail : $WORKDIR"
cd "$WORKDIR" || { echo "Erreur: impossible d'accéder au dossier $WORKDIR"; exit 1; }

clone_repo() {
    local repo_name=$1
    if [ ! -d "$repo_name" ]; then
        echo "Clonage du dépôt $repo_name..."
        git clone git@github.com:$GITHUB_USER/$repo_name.git || { echo "Erreur lors du clonage de $repo_name"; exit 1; }
    else
        echo "Le dépôt $repo_name existe déjà."
    fi
}

clone_repo "Ryvie"
clone_repo "Ryvie-rPictures"
clone_repo "Ryvie-rTransfer"
clone_repo "Ryvie-rdrop"

echo ""
echo "--------------------------------------------------"
echo "IMPORTANT :"
echo "Si vous venez d'ajouter votre utilisateur au groupe docker,"
echo "veuillez vous déconnecter/reconnecter ou lancer la commande suivante"
echo "dans un nouveau terminal pour appliquer les changements :"
echo "    newgrp docker"
echo "--------------------------------------------------"

echo ""
echo "Tout est prêt 🎉"
