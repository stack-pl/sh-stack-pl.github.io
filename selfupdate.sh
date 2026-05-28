#!/bin/bash

set -euo pipefail

# ==================================================
# Konfiguracja
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(realpath "$0")"

VERSION="1.2.0"

UPDATE_URL="https://sh.stack.pl/selfupdate.sh"
SHA256_URL="${UPDATE_URL}.sha256"

BACKUP_PATH="${SCRIPT_PATH}.bak"

LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"

TMP_FILE="$(mktemp)"
TMP_HASH="$(mktemp)"

# ==================================================
# Cleanup
# ==================================================

cleanup() {

    rm -f "$TMP_FILE" "$TMP_HASH"

    release_lock
}

# ==================================================
# Lockfile
# ==================================================

acquire_lock() {

    # Jeśli lock istnieje
    if [ -f "$LOCK_FILE" ]; then

        OLD_PID=$(cat "$LOCK_FILE")

        # Czy proces nadal działa?
        if kill -0 "$OLD_PID" >/dev/null 2>&1; then

            echo "Inna aktualizacja już działa."
            echo "PID: $OLD_PID"

            exit 1
        else
            echo "Usuwanie nieaktywnego lockfile."
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
}

release_lock() {

    rm -f "$LOCK_FILE"
}

# ==================================================
# Rollback
# ==================================================

rollback() {

    echo "BŁĄD aktualizacji — rollback..."

    if [ -f "$BACKUP_PATH" ]; then

        cp "$BACKUP_PATH" "$SCRIPT_PATH"

        chmod +x "$SCRIPT_PATH"

        echo "Przywrócono poprzednią wersję."

    else
        echo "Brak backupu!"
    fi

    cleanup

    exit 1
}

# ==================================================
# Wymagane narzędzia
# ==================================================

require_tools() {

    local tools=(
        curl
        sha256sum
        grep
        cut
        chmod
        cp
        mv
        sort
    )

    for tool in "${tools[@]}"; do

        if ! command -v "$tool" >/dev/null 2>&1; then

            echo "Brak wymaganego narzędzia: $tool"

            exit 1
        fi
    done
}

# ==================================================
# Semantic Versioning
# ==================================================

version_greater() {

    [ "$1" = "$2" ] && return 1

    local highest

    highest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)

    [ "$highest" = "$1" ]
}

# ==================================================
# Wersja
# ==================================================

print_version() {

    echo "$SCRIPT_NAME wersja $VERSION"
}

# ==================================================
# Pobieranie
# ==================================================

download_files() {

    echo "Pobieranie aktualizacji..."

    curl -fsSL "$UPDATE_URL" -o "$TMP_FILE"

    curl -fsSL "$SHA256_URL" -o "$TMP_HASH"
}

# ==================================================
# SHA256
# ==================================================

verify_checksum() {

    echo "Weryfikacja SHA256..."

    local expected_hash
    local actual_hash

    expected_hash=$(cut -d' ' -f1 "$TMP_HASH")

    actual_hash=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)

    echo "Expected : $expected_hash"
    echo "Actual   : $actual_hash"

    if [ "$expected_hash" != "$actual_hash" ]; then

        echo "BŁĄD: suma SHA256 jest niepoprawna."

        cleanup

        exit 1
    fi

    echo "SHA256 OK"
}

# ==================================================
# Odczyt wersji
# ==================================================

extract_new_version() {

    grep '^VERSION=' "$TMP_FILE" | head -n1 | cut -d'"' -f2
}

# ==================================================
# Aktualizacja
# ==================================================

update_script() {

    acquire_lock

    trap cleanup EXIT

    require_tools

    download_files

    verify_checksum

    local new_version

    new_version=$(extract_new_version)

    if [ -z "$new_version" ]; then

        echo "Nie udało się odczytać wersji."

        exit 1
    fi

    echo "Aktualna wersja : $VERSION"
    echo "Nowa wersja     : $new_version"

    # ==============================================
    # SemVer
    # ==============================================

    if [ "$new_version" = "$VERSION" ]; then

        echo "Skrypt jest aktualny."

        exit 0
    fi

    if ! version_greater "$new_version" "$VERSION"; then

        echo "Nowa wersja NIE jest nowsza."

        exit 0
    fi

    echo "Wykryto nową wersję."

    # ==============================================
    # Backup
    # ==============================================

    echo "Tworzenie backupu..."

    cp "$SCRIPT_PATH" "$BACKUP_PATH"

    # ==============================================
    # Instalacja
    # ==============================================

    echo "Instalowanie aktualizacji..."

    trap rollback ERR

    cp "$TMP_FILE" "$SCRIPT_PATH"

    chmod +x "$SCRIPT_PATH"

    trap - ERR

    echo "Aktualizacja zakończona sukcesem."

    echo "Backup:"
    echo "$BACKUP_PATH"
}

# ==================================================
# Main
# ==================================================

case "${1:-}" in

    update)
        update_script
        ;;

    version)
        print_version
        ;;

    *)
        echo "Uruchomiono główną logikę skryptu."
        ;;

esac
