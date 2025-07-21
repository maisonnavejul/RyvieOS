#!/bin/bash
set -e

echo "⚠️  Uninstall : suppression de tout l’environnement Ryvie OS..."

# 1) Arrêt et suppression des containers Docker et des stacks Docker Compose
echo "🛑 Arrêt des stacks Docker..."
for DIR in "$HOME/Bureau/ldap" "$HOME/Desktop/ldap" "$HOME/ldap"; do
  if [ -d "$DIR" ]; then
    echo " • $DIR"
    (cd "$DIR" && sudo docker compose down -v) || true
  fi
done

for NAME in Ryvie-rPictures Ryvie-rTransfer Ryvie-rdrop Ryvie; do
  for DIR in "$HOME/Bureau/$NAME" "$HOME/Desktop/$NAME" "$HOME/$NAME"; do
    if [ -d "$DIR" ]; then
      echo " • $DIR"
      (cd "$DIR" && sudo docker compose down -v) || true
    fi
  done
done

# 2) Suppression des volumes et réseaux Docker créés
echo "🗑️  Suppression des volumes et réseaux Docker..."
sudo docker volume rm openldap_data || true
sudo docker network rm my_custom_network || true
sudo docker system prune -af

# 3) Suppression des paquets apt
echo "📦 Suppression des paquets apt..."
sudo apt purge -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  ldap-utils npm avahi-daemon avahi-utils netbird \
  || true
sudo apt autoremove -y

# 4) Désinstallation de Node géré par 'n'
echo "📂 Suppression de 'n' et des binaires Node.js/npm..."
sudo npm uninstall -g n || true
sudo rm -f /usr/local/bin/n /usr/local/bin/node /usr/local/bin/npm
sudo rm -rf /usr/local/n

# 5) Retrait de l’utilisateur du groupe docker
echo "👤 Suppression de l’utilisateur $USER du groupe docker..."
sudo gpasswd -d "$USER" docker || true

# 6) Restauration de la config Avahi
echo "🔄 Restauration de /etc/avahi/avahi-daemon.conf..."
sudo sed -i 's/^host-name=.*/# host-name=ryvievmtest/' /etc/avahi/avahi-daemon.conf || true
sudo systemctl restart avahi-daemon

# 7) Suppression des dossiers clonés et des données locales
echo "📂 Suppression des répertoires locaux..."
for DIR in \
  "$HOME/Bureau/ldap" "$HOME/Desktop/ldap" "$HOME/ldap" \
  "$HOME/Bureau/Ryvie-rPictures" "$HOME/Desktop/Ryvie-rPictures" "$HOME/Ryvie-rPictures" \
  "$HOME/Bureau/Ryvie-rTransfer" "$HOME/Desktop/Ryvie-rTransfer" "$HOME/Ryvie-rTransfer" \
  "$HOME/Bureau/Ryvie-rdrop" "$HOME/Desktop/Ryvie-rdrop" "$HOME/Ryvie-rdrop" \
  "$HOME/Bureau/Ryvie" "$HOME/Desktop/Ryvie" "$HOME/Ryvie"
do
  if [ -e "$DIR" ]; then
    rm -rf "$DIR"
    echo " • supprimé $DIR"
  fi
done

echo ""
echo "✅ Désinstallation terminée. Redémarrez votre session ou votre machine pour valider."
