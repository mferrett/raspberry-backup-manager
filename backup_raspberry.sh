#!/bin/bash

# Directory di destinazione backup
BACKUP_ROOT="/media/esterno2/backup"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/backup_raspberry_$DATE"

# Percorsi da salvare
SUPERVISOR_CONF="/etc/supervisor/"
SYSTEMD_MAHA="/etc/systemd/system/maha_main.service"
SYSTEMD_UPDATE_IP="/etc/systemd/system/update_ip.service"
CRON_USER="pi"
PROFILE_FILE="/home/pi/.profile"
SMB_CONF="/etc/samba/smb.conf"
PLEX_DATA_DIR="/var/lib/plexmediaserver"
PLEX_CONFIG_DIR="/home/pi/.config/plex"

# Script da backup datato
SCRIPTS=("/home/pi/backup.sh" "/home/pi/restore_raspberry.sh")

# Cartelle da backup fisso (senza data)
HOME_FISSO_DIR="$BACKUP_ROOT/home"
HOME_FOLDERS=("data_probes" "go" "MAHA" "MAHA2" "rails" "travel_planner")

# Directory fissa per backup Plex (senza data)
PLEX_FISSO_DIR="$BACKUP_ROOT/plex"

# Creazione directory di backup datata
mkdir -p "$BACKUP_DIR"

# --- Backup supervisord ---
if [ -d "$SUPERVISOR_CONF" ]; then
    mkdir -p "$BACKUP_DIR/supervisor"
    cp -r "$SUPERVISOR_CONF"* "$BACKUP_DIR/supervisor/"
else
    echo "⚠️ Supervisord config non trovata in $SUPERVISOR_CONF"
fi

# --- Backup systemd maha_main ---
if [ -f "$SYSTEMD_MAHA" ]; then
    mkdir -p "$BACKUP_DIR/systemd"
    cp "$SYSTEMD_MAHA" "$BACKUP_DIR/systemd/"
else
    echo "⚠️ File systemd per maha_main non trovato"
fi

# --- Backup systemd update_ip ---
if [ -f "$SYSTEMD_UPDATE_IP" ]; then
    mkdir -p "$BACKUP_DIR/systemd"
    cp "$SYSTEMD_UPDATE_IP" "$BACKUP_DIR/systemd/"
else
    echo "⚠️ File systemd per update_ip non trovato"
fi

# --- Backup cron dell'utente pi ---
CRON_BACKUP="$BACKUP_DIR/cron/$CRON_USER.cron"
mkdir -p "$BACKUP_DIR/cron"
if crontab -l -u "$CRON_USER" &>/dev/null; then
    crontab -l -u "$CRON_USER" > "$CRON_BACKUP"
    echo "✅ Cron dell'utente $CRON_USER salvato in $CRON_BACKUP"
else
    echo "⚠️ Nessun cron trovato per utente $CRON_USER"
fi

# --- Backup .profile ---
if [ -f "$PROFILE_FILE" ]; then
    mkdir -p "$BACKUP_DIR/profile"
    cp "$PROFILE_FILE" "$BACKUP_DIR/profile/"
else
    echo "⚠️ File .profile non trovato"
fi

# --- Backup smb.conf ---
if [ -f "$SMB_CONF" ]; then
    mkdir -p "$BACKUP_DIR/samba"
    cp "$SMB_CONF" "$BACKUP_DIR/samba/"
else
    echo "⚠️ File smb.conf non trovato"
fi

# --- Backup dati Plex in destinazione fissa ---
# Backup directory principale dati Plex
if [ -d "$PLEX_DATA_DIR" ]; then
    mkdir -p "$PLEX_FISSO_DIR"
    echo "🎬 Avvio backup dati Plex da $PLEX_DATA_DIR..."
    # Rimuove il backup precedente e crea quello nuovo
    rm -rf "$PLEX_FISSO_DIR/plexmediaserver"
    mkdir -p "$PLEX_FISSO_DIR/plexmediaserver"
    # Copia tutto escludendo le cache e i file temporanei per velocizzare il backup
    rsync -av --exclude='Cache/' --exclude='Logs/' --exclude='Crash Reports/' \
          --exclude='Plug-in Support/Caches/' --exclude='*.tmp' \
          "$PLEX_DATA_DIR/" "$PLEX_FISSO_DIR/plexmediaserver/"
    echo "✅ Dati Plex salvati in $PLEX_FISSO_DIR/plexmediaserver/"
else
    echo "⚠️ Directory dati Plex $PLEX_DATA_DIR non trovata"
fi

# Backup configurazione Plex utente (se presente)
if [ -d "$PLEX_CONFIG_DIR" ]; then
    mkdir -p "$PLEX_FISSO_DIR"
    rm -rf "$PLEX_FISSO_DIR/config"
    cp -r "$PLEX_CONFIG_DIR" "$PLEX_FISSO_DIR/config/"
    echo "✅ Configurazione Plex utente salvata in $PLEX_FISSO_DIR/config/"
else
    echo "⚠️ Directory configurazione Plex $PLEX_CONFIG_DIR non trovata"
fi

# --- Backup script datati ---
mkdir -p "$BACKUP_DIR/scripts"
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        cp "$script" "$BACKUP_DIR/scripts/"
        echo "✅ Script $script salvato in $BACKUP_DIR/scripts/"
    else
        echo "⚠️ Script $script non trovato"
    fi
done

# --- Backup chiavi SSH ---
if [ -d "$SSH_DIR" ]; then
    mkdir -p "$BACKUP_DIR/ssh"
    cp -r "$SSH_DIR"/* "$BACKUP_DIR/ssh/"
    echo "✅ Chiavi SSH salvate in $BACKUP_DIR/ssh/"
else
    echo "⚠️ Cartella SSH $SSH_DIR non trovata"
fi

# --- Backup cartelle /home in destinazione fissa ---
mkdir -p "$HOME_FISSO_DIR"
for folder in "${HOME_FOLDERS[@]}"; do
    SRC="/home/pi/$folder"
    DEST="$HOME_FISSO_DIR/$folder"
    if [ -d "$SRC" ]; then
        rm -rf "$DEST"  # rimuove la vecchia copia
        cp -r "$SRC" "$DEST"
        echo "✅ Cartella $SRC copiata in $DEST"
    else
        echo "⚠️ Cartella $SRC non trovata"
    fi
done

echo "✅ Backup non compresso completato: $BACKUP_DIR"
echo "✅ Backup home in destinazione fissa completato: $HOME_FISSO_DIR"
echo "✅ Backup Plex in destinazione fissa completato: $PLEX_FISSO_DIR"

# --- Rimozione backup datati più vecchi di 30 giorni ---
if [ -d "$BACKUP_ROOT" ]; then
    find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d -name "backup_maha_*" -mtime +30 -exec rm -rf {} \;
    echo "🗑️ Backup datati più vecchi di 30 giorni rimossi"
fi

