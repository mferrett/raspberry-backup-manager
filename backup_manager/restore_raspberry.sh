#!/bin/bash

# ===============================
# Script di ripristino configurazioni Raspberry Pi
# ===============================

# Interrompi lo script in caso di errori
set -e
set -o pipefail

# Controllo argomento
if [ -z "$1" ]; then
    echo "Uso: $0 /percorso/del/backup"
    exit 1
fi

# Percorso della cartella di backup
BACKUP_DIR="$1"

# Utente di destinazione
USER_HOME="/home/pi"

# Funzione per installare un pacchetto se non presente
install_if_missing() {
    local pkg=$1
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "Installo $pkg..."
        sudo apt update
        sudo apt install -y "$pkg"
    else
        echo "$pkg è già installato."
    fi
}

# 1. Installare supervisord
install_if_missing "supervisor"

# 2. Configurare interfaccia supervisord su porta 9001
SUPERVISOR_CONF="/etc/supervisor/supervisord.conf"
if ! grep -q "9001" "$SUPERVISOR_CONF"; then
    echo "Configurazione supervisord sulla porta 9001..."
    sudo sed -i '/^\[inet_http_server\]/,/^\[/'d "$SUPERVISOR_CONF" 2>/dev/null
    echo -e "[inet_http_server]\nport=0.0.0.0:9001\nauthtoken=secret" | sudo tee -a "$SUPERVISOR_CONF"
fi

# Creazione directory log per travel_planner_webui
sudo mkdir -p /var/log/travel_planner_webui/
sudo chown pi:pi /var/log/travel_planner_webui/

# 3. Ripristinare i file di supervisord dalla directory di backup
if [ -d "$BACKUP_DIR/supervisord" ]; then
    echo "Ripristino configurazioni supervisord..."
    sudo cp -r "$BACKUP_DIR/supervisord/"* /etc/supervisor/conf.d/
    sudo supervisorctl reread
    sudo supervisorctl update
    sudo systemctl restart supervisor
fi

# 4. Ripristinare i file in /home/pi
#if [ -d "$BACKUP_DIR/home_pi" ]; then
#    echo "Ripristino file in $USER_HOME..."
#    cp -r "$BACKUP_DIR/home_pi/"* "$USER_HOME/"
#    chown -R pi:pi "$USER_HOME"
#fi

# 4.b Ripristino chiavi SSH dell'utente pi
SSH_BACKUP_DIR="$BACKUP_DIR/ssh"
SSH_HOME="$USER_HOME/.ssh"

if [ -d "$SSH_BACKUP_DIR" ]; then
    echo "Ripristino chiavi SSH per utente pi..."
    mkdir -p "$SSH_HOME"
    cp -r "$SSH_BACKUP_DIR/"* "$SSH_HOME/"
    chown -R pi:pi "$SSH_HOME"
    chmod 700 "$SSH_HOME"
    find "$SSH_HOME" -type f -name "id_*" -exec chmod 600 {} \;
    echo "Chiavi SSH ripristinate con successo."
else
    echo "Cartella SSH di backup non trovata, skip."
fi

# 4.c Ripristino cron dell'utente pi
CRON_BACKUP_DIR="$BACKUP_DIR/cron"

if [ -d "$CRON_BACKUP_DIR" ]; then
    if [ -f "$CRON_BACKUP_DIR/pi.cron" ]; then
        echo "Ripristino crontab per utente pi..."
        crontab -u pi "$CRON_BACKUP_DIR/pi.cron"
        echo "Crontab ripristinato."
    else
        echo "File cron pi.cron non trovato, skip."
    fi
else
    echo "Cartella cron di backup non trovata, skip."
fi

# 4.d Ripristino file .profile dell'utente pi
PROFILE_BACKUP_DIR="$BACKUP_DIR/profile"

if [ -f "$PROFILE_BACKUP_DIR/.profile" ]; then
    echo "Ripristino file .profile per utente pi..."
    cp "$PROFILE_BACKUP_DIR/.profile" "$USER_HOME/.profile"
    chown pi:pi "$USER_HOME/.profile"
    chmod 644 "$USER_HOME/.profile"
    echo ".profile ripristinato con successo."
else
    echo "File .profile di backup non trovato, skip."
fi




# 5. Installare Samba se necessario e ripristinare configurazioni
install_if_missing "samba"
if [ -d "$BACKUP_DIR/samba" ]; then
    echo "Ripristino configurazioni Samba..."
    sudo cp -r "$BACKUP_DIR/samba/"* /etc/samba/
fi

# Creazione utente Samba "pi" con password "raspberry"
if ! sudo pdbedit -L | grep -q "^pi:"; then
    echo -e "raspberry\nraspberry" | sudo smbpasswd -a pi
    echo "Utente Samba 'pi' creato con password 'raspberry'."
else
    echo "Utente Samba 'pi' già esistente."
fi

sudo systemctl restart smbd


# 6. Ripristinare cron dell'utente pi
#if [ -f "$BACKUP_DIR/cron/pi.cron" ]; then
#    echo "Ripristino cron per utente pi..."
#    crontab -u pi "$BACKUP_DIR/cron/pi.cron"
#fi

# 7. Ripristinare servizio systemd maha_main
if [ -f "$BACKUP_DIR/systemd/maha_main.service" ]; then
    echo "Ripristino servizio systemd maha_main..."
    sudo cp "$BACKUP_DIR/systemd/maha_main.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable maha_main
    sudo systemctl start maha_main
else
    echo "Servizio maha_main già installato, skip."
fi

# 8. Ripristinare servizio systemd update_ip
if [ -f "$BACKUP_DIR/systemd/update_ip.service" ]; then
    echo "Ripristino servizio systemd update_ip..."
    sudo cp "$BACKUP_DIR/systemd/update_ip.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable update_ip
    sudo systemctl start update_ip
else
    echo "Servizio update_ip già installato, skip."
fi

# 8. Installazione Plex Media Server (solo se non presente)
if ! dpkg -s plexmediaserver &> /dev/null; then
    echo "Installazione Plex Media Server..."

    # Aggiungo repository ufficiale Plex (solo se non già presente)
    if [ ! -f /etc/apt/sources.list.d/plexmediaserver.list ]; then
        wget -q https://downloads.plex.tv/plex-keys/PlexSign.key -O - | sudo apt-key add -
        echo "deb https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
    fi

    # Aggiorno pacchetti e installo Plex
    sudo apt update
    sudo apt install -y plexmediaserver

    # Avvio e abilitazione del servizio
    sudo systemctl enable plexmediaserver
    sudo systemctl start plexmediaserver

    echo "Plex Media Server installato e avviato."
else
    echo "Plex Media Server è già installato."
fi

# 8.b Ripristino dati Plex dal backup
echo "Controllo backup dati Plex..."

# Directory di destinazione dati Plex
PLEX_DATA_DIR="/var/lib/plexmediaserver"
PLEX_CONFIG_DIR="/home/pi/.config/plex"

# Ferma il servizio Plex prima del ripristino
if systemctl is-active --quiet plexmediaserver; then
    echo "Arresto temporaneo di Plex Media Server per il ripristino..."
    sudo systemctl stop plexmediaserver
    PLEX_WAS_RUNNING=true
else
    PLEX_WAS_RUNNING=false
fi

# Ripristino directory principale dati Plex
if [ -d "$BACKUP_DIR/plex/plexmediaserver" ]; then
    echo "🎬 Ripristino dati Plex in $PLEX_DATA_DIR..."
    
    # Backup della configurazione esistente se presente
    if [ -d "$PLEX_DATA_DIR" ]; then
        echo "Backup configurazione Plex esistente..."
        sudo mv "$PLEX_DATA_DIR" "${PLEX_DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Crea directory e ripristina i dati
    sudo mkdir -p "$PLEX_DATA_DIR"
    sudo rsync -av "$BACKUP_DIR/plex/plexmediaserver/" "$PLEX_DATA_DIR/"
    
    # Imposta i permessi corretti
    sudo chown -R plex:plex "$PLEX_DATA_DIR"
    sudo chmod -R 755 "$PLEX_DATA_DIR"
    
    echo "✅ Dati Plex ripristinati in $PLEX_DATA_DIR"
else
    echo "⚠️ Backup dati Plex non trovato in $BACKUP_DIR/plex/plexmediaserver, skip."
fi

# Ripristino configurazione Plex utente (se presente)
if [ -d "$BACKUP_DIR/plex/config" ]; then
    echo "Ripristino configurazione Plex utente in $PLEX_CONFIG_DIR..."
    
    # Crea directory se non esiste
    mkdir -p "$PLEX_CONFIG_DIR"
    
    # Ripristina configurazione
    cp -r "$BACKUP_DIR/plex/config/"* "$PLEX_CONFIG_DIR/"
    
    # Imposta permessi corretti
    chown -R pi:pi "$PLEX_CONFIG_DIR"
    
    echo "✅ Configurazione Plex utente ripristinata in $PLEX_CONFIG_DIR"
else
    echo "⚠️ Backup configurazione Plex utente non trovato, skip."
fi

# Riavvia Plex se era in esecuzione
if [ "$PLEX_WAS_RUNNING" = true ]; then
    echo "Riavvio Plex Media Server..."
    sudo systemctl start plexmediaserver
    echo "✅ Plex Media Server riavviato con successo"
fi

# 9. Configurazione Certbot con challenge custom
DOMAIN="diveintomic.no-ip.org"
CHALLENGE_DIR="/home/pi/MAHA2/dist/.well-known/acme-challenge/"

echo "Installazione Certbot..."
sudo apt install -y certbot

# Creazione directory challenge
sudo mkdir -p "$CHALLENGE_DIR"
sudo chown -R pi:pi /home/pi/MAHA2

echo "Richiesta certificato per $DOMAIN su porta 8443..."
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    sudo certbot certonly \
        --webroot -w "$CHALLENGE_DIR" \
        -d "$DOMAIN" \
        --agree-tos \
        --non-interactive \
        --register-unsafely-without-email \
        --http-01-port 8443
    echo "Certificato ottenuto con successo per $DOMAIN"
else
    echo "Certificato già presente per $DOMAIN, skip."
fi

# Aggiungo cron per rinnovo automatico
CRON_LINE="0 3 * * * certbot renew --quiet --http-01-port 8443 --webroot -w $CHALLENGE_DIR"
( crontab -l 2>/dev/null | grep -v "certbot renew" ; echo "$CRON_LINE" ) | crontab -


# 10. Installazione e configurazione Webmin
echo "Controllo presenza Webmin..."
if ! dpkg -l | grep -q webmin; then
    echo "Installazione Webmin..."
    sudo apt install -y wget apt-transport-https software-properties-common
    wget -q -O- http://www.webmin.com/jcameron-key.asc | sudo apt-key add -
    sudo add-apt-repository "deb http://download.webmin.com/download/repository sarge contrib"
    sudo apt update
    sudo apt install -y webmin
    sudo systemctl enable webmin
    sudo systemctl start webmin
    echo "Webmin installato e avviato su porta 10000."
else
    echo "Webmin già installato, skip."
fi


# 11. Aggiunta riga in /etc/fstab per montaggio disco esterno
FSTAB_LINE="/dev/sda1    /media/esterno2    ext4    defaults    0    0"
MOUNT_POINT="/media/esterno2"

echo "Configurazione fstab per disco esterno..."
# Creazione punto di mount se non esiste
sudo mkdir -p "$MOUNT_POINT"

# Aggiunge la riga solo se /media/esterno2 non è già presente
if ! grep -q "/media/esterno2" /etc/fstab; then
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab
    echo "Riga aggiunta a /etc/fstab."
else
    echo "/media/esterno2 già presente in /etc/fstab, skip."
fi

# Montaggio immediato del disco
echo "Montaggio disco /dev/sda1 su $MOUNT_POINT..."
sudo mount "$MOUNT_POINT"
echo "Disco montato."



echo "Ripristino completato!"
