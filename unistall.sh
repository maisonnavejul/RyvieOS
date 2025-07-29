#!/bin/bash

echo ""
echo "=============================================="
echo " Désinstallation complète de Ryvie OS "
echo "=============================================="
echo ""

# -------------------------------------------------------------------
# Étape 1: Arrêt et suppression des conteneurs Docker
# -------------------------------------------------------------------
echo "Arrêt et suppression des conteneurs Docker..."
sudo docker stop openldap 2>/dev/null
sudo docker rm openldap 2>/dev/null

# Suppression des services Ryvie
sudo docker compose -f ~/Bureau/Ryvie-rPictures/docker/docker-compose.ryvie.yml down 2>/dev/null
sudo docker compose -f ~/Bureau/Ryvie-rTransfer/docker-compose.local.yml down 2>/dev/null
sudo docker compose -f ~/Desktop/Ryvie-rdrop/snapdrop-master/docker-compose.yml down 2>/dev/null
sudo docker compose -f ~/Bureau/ldap/docker-compose.yml down 2>/dev/null

# -------------------------------------------------------------------
# Étape 2: Suppression des réseaux Docker
# -------------------------------------------------------------------
echo "Suppression des réseaux Docker..."
sudo docker network rm my_custom_network 2>/dev/null
sudo docker network prune -f

# -------------------------------------------------------------------
# Étape 3: Suppression des volumes Docker
# -------------------------------------------------------------------
echo "Suppression des volumes Docker..."
sudo docker volume rm openldap_data 2>/dev/null
sudo docker volume rm $(sudo docker volume ls -q | grep -E 'rtransfer|immich|snapdrop') 2>/dev/null
sudo docker volume prune -f

# -------------------------------------------------------------------
# Étape 4: Suppression des images Docker
# -------------------------------------------------------------------
echo "Suppression des images Docker..."
sudo docker rmi bitnami/openldap:latest 2>/dev/null
sudo docker rmi $(sudo docker images -q | grep -E 'rtransfer|immich|snapdrop') 2>/dev/null

# -------------------------------------------------------------------
# Étape 5: Suppression des fichiers et répertoires
# -------------------------------------------------------------------
echo "Suppression des fichiers et répertoires..."
rm -rf ~/Bureau/ldap 2>/dev/null
rm -rf ~/Bureau/Ryvie-rPictures 2>/dev/null
rm -rf ~/Bureau/Ryvie-rTransfer 2>/dev/null
rm -rf ~/Bureau/Ryvie-rdrop 2>/dev/null
rm -rf ~/Bureau/Ryvie 2>/dev/null
rm -rf ~/Desktop/ldap 2>/dev/null
rm -rf ~/Desktop/Ryvie-rPictures 2>/dev/null
rm -rf ~/Desktop/Ryvie-rTransfer 2>/dev/null
rm -rf ~/Desktop/Ryvie-rdrop 2>/dev/null
rm -rf ~/Desktop/Ryvie 2>/dev/null

# -------------------------------------------------------------------
# Étape 6: Suppression des dépendances (optionnel)
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer les dépendances installées ? (docker, node, npm) [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]
then
    echo "Désinstallation de Docker..."
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo rm -rf /etc/apt/keyrings/docker.gpg
    sudo rm -rf /etc/apt/sources.list.d/docker.list

    echo "Désinstallation de Node.js et npm..."
    sudo npm uninstall -g n
    sudo apt purge -y npm nodejs
    sudo rm -rf /usr/local/bin/n
    sudo rm -rf /usr/local/n
    sudo rm -rf ~/.npm
fi

# -------------------------------------------------------------------
# Étape 7: Retrait de l'utilisateur du groupe docker
# -------------------------------------------------------------------
read -p "Voulez-vous retirer l'utilisateur du groupe docker ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]
then
    sudo deluser $USER docker
    echo "Vous avez été retiré du groupe docker. Une déconnexion est nécessaire."
fi

# -------------------------------------------------------------------
# Étape 8: Nettoyage final
# -------------------------------------------------------------------
echo "Nettoyage final..."
sudo apt autoremove -y
sudo apt clean

# -------------------------------------------------------------------
# Étape 9: Suppression du service Avahi (optionnel)
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer le service Avahi (ryvie.local) ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]
then
    sudo apt purge -y avahi-daemon avahi-utils
    sudo rm -rf /etc/avahi/avahi-daemon.conf
fi

# -------------------------------------------------------------------
# Étape 10: Suppression des données utilisateur
# -------------------------------------------------------------------
read -p "Voulez-vous supprimer les données utilisateur et de configuration ? [N/o] " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]
then
    rm -rf ~/.config/rtransfer 2>/dev/null
    rm -rf ~/.cache/immich 2>/dev/null
    rm -rf ~/.local/share/snapdrop 2>/dev/null
fi

echo ""
echo "=============================================="
echo " Désinstallation terminée avec succès ! "
echo "=============================================="
echo "Tous les composants Ryvie OS ont été supprimés."
echo "Il est recommandé de redémarrer votre système."
echo ""
