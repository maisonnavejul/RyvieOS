echo ""
echo "=============================================="
echo " Désinstallation complète de Ryvie OS "
echo "=============================================="
echo ""

# -------------------------------------------------------------------
# Étape 1: Arrêt et suppression de TOUS les conteneurs Docker
# -------------------------------------------------------------------
echo "Arrêt et suppression de tous les conteneurs Docker..."
sudo docker stop $(sudo docker ps -aq) 2>/dev/null
sudo docker rm $(sudo docker ps -aq) 2>/dev/null

# -------------------------------------------------------------------
# Étape 2: Suppression de TOUS les services Docker Compose Ryvie
# -------------------------------------------------------------------
echo "Arrêt des services Docker Compose Ryvie..."
sudo docker compose -f ~/Bureau/Ryvie-rPictures/docker/docker-compose.ryvie.yml down 2>/dev/null
sudo docker compose -f ~/Bureau/Ryvie-rTransfer/docker-compose.local.yml down 2>/dev/null
sudo docker compose -f ~/Desktop/Ryvie-rdrop/snapdrop-master/docker-compose.yml down 2>/dev/null
sudo docker compose -f ~/Bureau/ldap/docker-compose.yml down 2>/dev/null

# -------------------------------------------------------------------
# Étape 3: Suppression de TOUS les réseaux Docker
# -------------------------------------------------------------------
echo "Suppression de tous les réseaux Docker..."
sudo docker network prune -f

# -------------------------------------------------------------------
# Étape 4: Suppression de TOUS les volumes Docker
# -------------------------------------------------------------------
echo "Suppression de tous les volumes Docker..."
sudo docker volume prune -f


# -------------------------------------------------------------------
# Étape 6: Suppression de tous les dossiers Ryvie
# -------------------------------------------------------------------
echo "Suppression des dossiers Ryvie..."
find ~ -type d -iname "Ryvie*" -exec rm -rf {} + 2>/dev/null
find ~/Bureau -type d -iname "Ryvie*" -exec rm -rf {} + 2>/dev/null
find ~/Desktop -type d -iname "Ryvie*" -exec rm -rf {} + 2>/dev/null
rm -rf ~/Bureau/ldap ~/Desktop/ldap ~/ldap 2>/dev/null
# -------------------------------------------------------------------
# Étape 6: Suppression de tous les dossiers Ryvie (forcée)
# -------------------------------------------------------------------
echo "Suppression des dossiers Ryvie..."

# Liste de tous les emplacements typiques
PATHS_TO_DELETE=(
    "$HOME/Bureau/Ryvie*"
    "$HOME/Desktop/Ryvie*"
    "$HOME/Ryvie*"
    "$HOME/Bureau/ldap"
    "$HOME/Desktop/ldap"
    "$HOME/ldap"
)

for path in "${PATHS_TO_DELETE[@]}"; do
    echo "Suppression de $path"
    sudo rm -rf $path 2>/dev/null
done

# On vérifie si quelque chose reste (debug)
find ~ -type d -iname "Ryvie*" -exec echo "⚠️ Non supprimé: {}" \;

# -------------------------------------------------------------------
# Étape 7: Suppression des dépendances (optionnel)
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer les dépendances installées ? (docker, node, npm) [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    echo "Désinstallation de Docker..."
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo rm -rf /etc/apt/keyrings/docker.gpg /etc/apt/sources.list.d/docker.list

    echo "Désinstallation de Node.js et npm..."
    sudo npm uninstall -g n
    sudo apt purge -y npm nodejs
    sudo rm -rf /usr/local/bin/n /usr/local/n ~/.npm
fi

# -------------------------------------------------------------------
# Étape 8: Retrait de l'utilisateur du groupe docker
# -------------------------------------------------------------------
read -p "Voulez-vous retirer l'utilisateur du groupe docker ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    sudo deluser $USER docker
    echo "Vous avez été retiré du groupe docker. Une déconnexion est nécessaire."
fi

# -------------------------------------------------------------------
# Étape 9: Nettoyage final
# -------------------------------------------------------------------
echo "Nettoyage final..."
sudo apt autoremove -y
sudo apt clean

# -------------------------------------------------------------------
# Étape 10: Suppression du service Avahi (optionnel)
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer le service Avahi (ryvie.local) ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    sudo apt purge -y avahi-daemon avahi-utils
    sudo rm -rf /etc/avahi/avahi-daemon.conf
fi

# -------------------------------------------------------------------
# Étape 11: Suppression des données utilisateur (optionnel)
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer les données utilisateur et de configuration ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    rm -rf ~/.config/rtransfer ~/.cache/immich ~/.local/share/snapdrop 2>/dev/null
fi

echo ""
echo "=============================================="
echo " Désinstallation terminée avec succès ! "
echo "=============================================="
echo "Tous les composants Docker et Ryvie OS ont été supprimés."
echo "Il est recommandé de redémarrer votre système."
echo ""
