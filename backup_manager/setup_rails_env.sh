#!/bin/bash

# =====================================================================
# Script di ripristino delll'ambiente di sviluppo Rails su Raspberry Pi
# =====================================================================

# Versione di Ruby predefinita
RUBY_VERSION="${1:-3.3.7}"

# Verifica degli argomenti
if [[ $1 == "-h" ]] || [[ $1 == "--help" ]]; then
    echo "Utilizzo: $0 [VERSIONE_RUBY]"
    echo ""
    echo "Argomenti:"
    echo "  VERSIONE_RUBY    Versione di Ruby da installare (default: 3.3.7)"
    echo "  -h, --help       Mostra questo messaggio di aiuto"
    echo ""
    echo "Esempi:"
    echo "  $0                  # Installa Ruby 3.3.7"
    echo "  $0 3.2.5           # Installa Ruby 3.2.5"
    echo "  $0 3.4.0           # Installa Ruby 3.4.0"
    exit 0
fi

# Interrompi lo script in caso di errori
set -e
set -o pipefail

# =====================================================================
# Funzione di utilità per controllare la presenza di un pacchetto
# =====================================================================
check_package() {
    local package=$1
    if dpkg -l | grep -q "^ii  $package"; then
        return 0
    else
        return 1
    fi
}

# =====================================================================
# Funzione di utilità per controllare la presenza di un comando
# =====================================================================
check_command() {
    local command=$1
    if command -v $command &> /dev/null; then
        return 0
    else
        return 1
    fi
}

echo "====================================================================="
echo "Setup Rails Environment - Ruby versione: $RUBY_VERSION"
echo "====================================================================="
echo ""

# =====================================================================
# Installazione di rvm
# =====================================================================
echo "Installazione di rvm..."
if ! check_command rvm; then
    echo "rvm non trovato, procedo con l'installazione..."
    curl -sSL https://get.rvm.io | bash -s stable
    source $HOME/.rvm/scripts/rvm
    echo "✓ rvm installato con successo"
else
    echo "✓ rvm è già installato"
    source $HOME/.rvm/scripts/rvm
fi

# =====================================================================
# Installazione di Ruby $RUBY_VERSION
# =====================================================================
echo "Installazione di Ruby $RUBY_VERSION..."
source $HOME/.rvm/scripts/rvm
if rvm list | grep -q "ruby-$RUBY_VERSION"; then
    echo "✓ Ruby $RUBY_VERSION è già installato"
else
    echo "Ruby $RUBY_VERSION non trovato, procedo con l'installazione..."
    rvm install ruby-$RUBY_VERSION
fi
rvm use ruby-$RUBY_VERSION --default
echo "✓ Ruby $RUBY_VERSION impostato come versione predefinita"


# =====================================================================
# Aggiornamento dei pacchetti di sistema
# =====================================================================
echo "Aggiornamento dei pacchetti di sistema..."
sudo apt update
sudo apt upgrade -y
echo "✓ Pacchetti di sistema aggiornati"

# =====================================================================
# Installazione di MariaDB
# =====================================================================
echo "Installazione di MariaDB..."
if check_package mariadb-server; then
    echo "✓ MariaDB è già installato"
else
    echo "MariaDB non trovato, procedo con l'installazione..."
    sudo apt install mariadb-server mariadb-client -y
fi
sudo systemctl enable mariadb
sudo systemctl start mariadb
if sudo systemctl is-active --quiet mariadb; then
    echo "✓ MariaDB avviato e abilitato al boot"
else
    echo "⚠ Errore nell'avvio di MariaDB"
    exit 1
fi

# =====================================================================
# Configurazione di MariaDB - bind-address
# =====================================================================
echo "Configurazione di MariaDB per accettare connessioni da qualsiasi indirizzo..."
MARIADB_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"

if [ -f "$MARIADB_CONFIG" ]; then
    if ! grep -q "bind-address = 0.0.0.0" "$MARIADB_CONFIG"; then
        # Commenta la vecchia configurazione bind-address se esiste
        sudo sed -i 's/^bind-address = 127.0.0.1/#bind-address = 127.0.0.1/' "$MARIADB_CONFIG"
        # Aggiungi la nuova configurazione
        sudo sed -i '/\[mysqld\]/a bind-address = 0.0.0.0' "$MARIADB_CONFIG"
        sudo systemctl restart mariadb
        echo "✓ MariaDB configurato per accettare connessioni da qualsiasi indirizzo"
    else
        echo "✓ bind-address già configurato a 0.0.0.0"
    fi
else
    echo "⚠ File di configurazione MariaDB non trovato: $MARIADB_CONFIG"
fi

# =====================================================================
# Creazione dell'utente e del database di MariaDB
# =====================================================================
echo "Creazione dell'utente casaparrina e del database..."

# Verifica se l'utente esiste già
USER_EXISTS=$(sudo mysql -e "SELECT COUNT(*) FROM mysql.user WHERE user='casaparrina';" 2>/dev/null | tail -1)

if [ "$USER_EXISTS" -eq 0 ]; then
    # Crea l'utente e il database
    sudo mysql -e "CREATE USER 'casaparrina'@'%' IDENTIFIED BY 'JpyL8Vq4{6?.'"
    sudo mysql -e "CREATE DATABASE casaparrina_development CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "GRANT ALL PRIVILEGES ON casaparrina_development.* TO 'casaparrina'@'%';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    echo "✓ Utente casaparrina creato con successo"
    echo "✓ Database casaparrina_development creato con successo"
else
    echo "✓ Utente casaparrina esiste già"
fi


echo "Installazione delle dipendenze di sistema per Rails..."
dependencies=("build-essential" "libmariadb-dev" "libssl-dev" "zlib1g-dev")

for dep in "${dependencies[@]}"; do
    if check_package $dep; then
        echo "✓ $dep è già installato"
    else
        echo "Installazione di $dep..."
        sudo apt install $dep -y
    fi
done
echo "✓ Dipendenze di sistema installate con successo"

# =====================================================================
# Installazione della gem mysql2
# =====================================================================
echo "Installazione della gem mysql2..."
if gem list | grep -q "^mysql2"; then
    echo "✓ mysql2 è già installato"
else
    echo "Installazione di mysql2..."
    gem install mysql2 -v '0.5.6' -- --with-mysql-config=/usr/bin/mariadb_config
fi
echo "✓ mysql2 installato con successo"

# =====================================================================
# Configurazione di Bundle
# =====================================================================
echo "Configurazione di Bundle..."
bundle config build.mysql2 "--with-mysql-config=/usr/bin/mariadb_config"
bundle install
echo "✓ Bundle install concluso con successo"

echo ""
echo "=====================================================================
echo "✓ Setup completato con successo!"
echo "====================================================================="
