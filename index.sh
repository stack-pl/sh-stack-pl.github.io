
##### SELF UPDATE SECTION #####
# This section is responsible for updating the script itself.
# It checks for updates on the specified URL and replaces the current script if a new version is available.

SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(realpath "$0")"

VERSION="1.0.3"
DESCRIPTION="Generate index.html with links to all .sh files in the current directory and subdirectories, along with their SHA-256 checksums."

UPDATE_URL="https://sh.stack.pl/index.sh"
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
    exit 1 || return 1
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
            exit 1 || return 1
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
    echo "$SCRIPT_NAME  $VERSION"
}

# ==================================================
# Pobieranie
# ==================================================
download_files() {
    echo curl -fsSL "$UPDATE_URL" -o "$TMP_FILE"
    curl -fsSL "$UPDATE_URL" -o "$TMP_FILE"
    if [ $? -ne 0 ]; then
        echo "BŁĄD: Nie można pobrać aktualizacji z $UPDATE_URL"
        cleanup
        exit 1 || return 1
    fi
    echo curl -fsSL "$SHA256_URL" -o "$TMP_HASH"
    curl -fsSL "$SHA256_URL" -o "$TMP_HASH"
    if [ $? -ne 0 ]; then
        echo "BŁĄD: Nie można pobrać sumy kontrolnej z $SHA256_URL"
        cleanup
        exit 1 || return 1
    fi
}

# ==================================================
# SHA256
# ==================================================
verify_checksum() {
    local expected_hash
    local actual_hash
    expected_hash=$(cut -d' ' -f1 "$TMP_HASH")
    actual_hash=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)
    if [ "$expected_hash" != "$actual_hash" ]; then
        echo "BŁĄD: suma SHA256 jest niepoprawna."
        echo "Expected : $expected_hash"
        echo "Actual   : $actual_hash"
        cleanup
        exit 1 || return 1
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
        exit 1 || return 1
    fi
    echo "Aktualna wersja : $VERSION"
    echo "Nowa wersja     : $new_version"
    # ==============================================
    # SemVer
    # ==============================================
    if [ "$new_version" = "$VERSION" ]; then
        local current_script_hash
        local server_script_hash
        current_script_hash=$(sha256sum "$SCRIPT_PATH" | cut -d' ' -f1)
        server_script_hash=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)
        if [ "$current_script_hash" != "$server_script_hash" ]; then
            echo "Deklarowana wersja skryptów: lokalnego i z serwera jest taka sama, ale różnią się zawartością. Możliwe, że aktualizacja została wydana bez zmiany numeru wersji lub lokalny skrypt został zmodyfikowany. Przerywam aktualizację."
            exit 1 || return 1
        else
            echo "Skrypt jest aktualny."
            exit 0 || return 0
        fi
    fi
    if ! version_greater "$new_version" "$VERSION"; then
        echo "Skrypt lokalny jest nowszy niż dostępna aktualizacja. Przerywam aktualizację."
        exit 0 || return 0
    fi
    echo "Wykryto nową wersję."
    # ==============================================
    # Backup
    # ==============================================
    echo "Tworzenie backupu aktualnej wersji skryptu w $BACKUP_PATH"
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
}

generate() {
    echo "Generating index.html..."
    find . -type f -name "*.sh" -not -name '*index.html*' -not -path '*.sha256' -not -path './.*' \
    | sort \
    | awk \
    '
    BEGIN {
        print "<html>"
        print "  <head>"
        print "    <title>stack.pl operational facilities</title>"
        print "    <meta charset=\"UTF-8\">"
        print "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        print "    <style>"
        print "      body {"
        print "        font-family: Arial, sans-serif;"
        print "        margin: 20px;"
        print "      }"
        print "      h1 {"
        print "         color: #333;"
        print "      }"
        print "      p {"
        print "       font-size: 16px;"
        print "        color: #555;"
        print "      }"

        print "      ul.scripts-list {"
        print "        list-style: none;"
        print "        padding: 0;"
        print "        margin: 12px 0;"
        print "        border: 1px solid #e6e6e6;"
        print "        border-radius: 6px;"
        print "        overflow: hidden;"
        print "        background: #fff;"
        print "      }"

        print "      ul.scripts-list .row {"
        print "        display: grid;"
        print "        grid-template-columns: 150px 1fr 150px;"
        print "        gap: 12px;"
        print "        align-items: center;"
        print "        padding: 10px 12px;"
        print "      }"

        print "      ul.scripts-list .row.header {"
        print "        background: #f7f7f7;"
        print "        font-weight: 700;"
        print "        color: #222;"
        print "      }"

        print "      /* Odstęp między wierszami */"
        print "      ul.scripts-list .row + .row {"
        print "        border-top: 1px solid #f0f0f0;"
        print "      }"

        print "      ul.scripts-list a {"
        print "        color: #0066cc;"
        print "        text-decoration: none;"
        print "      }"

        print "      ul.scripts-list a:hover {"
        print "        text-decoration: underline;"
        print "      }"

        print "      .col.sha code {"
        print "        font-family: \"SFMono-Regular\", Consolas, \"Liberation Mono\", monospace;"
        print "        font-size: 0.95em;"
        print "        color: #333;"
        print "        word-break: break-all;"
        print "      }"

        print "      /* Małe urządzenia: dopasuj kolumny */"
        print "      @media (max-width: 700px) {"
        print "        ul.scripts-list .row {"
        print "          grid-template-columns: 1fr;"
        print "          gap: 6px;"
        print "          padding: 8px 10px;"
        print "        }"
        print "        ul.scripts-list .row.header {"
        print "          display: none;"
        print "        }"
        print "      }"
        print "    </style>"
        print "  </head>"
        print "  <body>"
        print "    <p>"
        print "      stack.pl operational facilities"
        print "    </p>"
        print "    <ul class=\"scripts-list\" role=\"table\" aria-label=\"Script files\">"
        print "      <li class=\"row header\" role=\"row\">"
        print "        <span class=\"col name\" role=\"columnheader\">Tool</span>"
        print "        <span class=\"col desc\" role=\"columnheader\">Description</span>"
        print "        <span class=\"col sha\" role=\"columnheader\">SHA-256</span>"
        print "      </li>"
    }
    {
        n=split($0, pathArray, "/")
        name=pathArray[n]
        cmdresult="";
        cmd="sha256sum " $0 " 2>/dev/null";
        if ( (cmd | getline line) > 0 ){
            cmdresult=line
            close(cmd)
        }
        split(cmdresult, row, " ");
        digest=row[1]
        cmd="echo \047" cmdresult "\047> " name ".sha256" ;
        system(cmd);
        cmdresult="";
        cmd="grep ^VERSION= " name " | head -n1 | cut -d\047\042\047 -f2" ;
        if ( (cmd | getline line) > 0 ){
            cmdresult=line
            close(cmd)
        }
        version="";
        if ( cmdresult != "" ) {
            version=cmdresult
        }
        cmdresult="";
        cmd="grep ^DESCRIPTION= " name " | head -n1 | cut -d\047\042\047 -f2" ;
        if ( (cmd | getline line) > 0 ){
            cmdresult=line
            close(cmd)
        }
        description="";
        if ( cmdresult != "" ) {
            description=cmdresult
        }
        getcommand="curl -LsSf https://sh.stack.pl/"name" > "name" "
        print "      <li class=\"row\" role=\"row\">"
        print "        <a class=\"col name\" role=\"cell\" href=\" " name " \" title=\""name " " version "\">" name "</a>"
        print "        <span class=\"col desc\" role=\"cell\"><p>" description "</p><code>" getcommand "</code></span>"
        print "        <span class=\"col sha\" role=\"cell\"><code>" digest "</code></span>"
        print "      </li>"
    } 
    END {
        print "    </ul>"
        print "  </body>"
        print "</html>"
    }
    ' > index.html
    echo "index.html generated successfully."
}

help-script() {
    echo "Usage: index.sh [ help | generate | update | version ]"
    echo
    echo "  index.sh  help                - show this help message"
    echo "  index.sh  generate            - create new index.html file with links to" 
    echo "                                  all files in the current directory and "
    echo "                                  subdirectories"
    echo "  index.sh  update              - update this script to the latest version"
    echo "  index.sh  version             - show script version"
    echo 
    echo "DESCRIPTION:"
    echo "  $DESCRIPTION"
    echo 
    echo
    echo "  Dariusz Chilimoniuk, https://stack.pl"
    echo "                       https://github.com/stack-pl/sh-stack-pl.github.io "
    echo
}
###### MAIN LOGIC ######

case "${1:-}" in
    generate)
        generate
        ;;
    update)
        update_script
        ;;
    version)
        print_version
        ;;
    help)
        help-script
        ;;
    *)
        echo "$DESCRIPTION"
        echo
        echo "Run  'sync.sh help'  for usage instructions"
        echo
        ;;
esac
