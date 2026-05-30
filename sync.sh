#!/bin/env bash 

# set -euo pipefail

#### DEFAULT SETTINGS SECTION ####
# The lines below are the settings for the rest of the script. 
# You can edit these parameters to fit your needs. Make sure to set the remote host, user, and directories according to your requirements. Always double-check the directories and confirm the actions to avoid accidental data loss. Use this script responsibly and make sure you have backups of your data before deploying changes to the server.

# Remote SSH host (it can be an IP address, a domain name, 
# or a hostname defined in your SSH config).
remote_ssh_host="do1"

# Remote SSH user
remote_ssh_user="root"

# Remote rsync directory (note the trailing slash)
# Full path to the directory on the remote server where you want to sync files.
remote_dir="/var/www/h1.stack.pl/"

# Remote files ownership settings. Files deployed to the server will be owned by this user.
remote_files_owner=$remote_ssh_user

# Remote files group settings. Files deployed to the server will belong to this group.
remote_files_group=$remote_ssh_user

# rn=$(basename "$remote_dir")

# Below are two local directories for rsync. 
# You can set them to the same path if you want, 
# but it is safer to keep them separate.
# Choose different paths to avoid accidental overwriting of files.

# Local rsync directory for files received from server (note the trailing slash)
local_backup_dir="backup/"

# Local rsync directory for files to be sent to server (note the trailing slash)
local_deploy_dir="deploy/"

# Local rsync directory for rotation (note the trailing slash).
# This directory will be used to store rotated copies of the backup directory
# when changes are detected and deploy directory when changes are detected before
# deploying to the server.
local_rotate_dir="rotate/"

### This is the base path for your local Git repository you want to deploy.
# It should be path out of this project directory.
local_repository_base_path="~/projects/repo/"

### This is the path to the directory in your local repository where files to be deployed are located.
# Leave it empty if you want to deploy files from the root of the repository, 
# or set it to a subdirectory if you want to deploy only part of the repository.
# This path is interpreted relative to the preceding local_repository_base_path. 
# For example, if your repository is at /home/user/repo and you want to deploy 
# files from /home/user/repo/dist, set local_repository_base_path to /home/user/repo/ 
# and local_repository_deploy_path to dist/
local_repository_deploy_path=""

### This is the branch in your local repository that you want to deploy.
local_repository_branch="main"

##### SELF UPDATE SECTION #####
# This section is responsible for updating the script itself.
# It checks for updates on the specified URL and replaces the current script if a new version is available.

SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(realpath "$0")"

VERSION="1.1.4"
DESCRIPTION="Script for synchronizing files between a local directory and a remote server using rsync and SSH. It includes features like backup, deploy, rotate."

UPDATE_URL="https://sh.stack.pl/sync.sh"
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


##### VALIDATION SECTION #####
check_directory_path () {
    if [[ ! "${1: -1:1}" == $'/' ]]; then
        echo "ERROR:"
        echo "  Directory does not end with a slash character."
        echo "    Current path:  $1"
        echo "    Expected path: $1/"
        echo "  Edit the '$2' in settings file and try again."
        echo
        exit 1 || return 1
    fi 
}

check_directory_path "$remote_dir" "remote_dir"
check_directory_path "$local_backup_dir" "local_backup_dir"
check_directory_path "$local_deploy_dir" "local_deploy_dir"
check_directory_path "$local_rotate_dir" "local_rotate_dir"

full_path(){
    if [[ -d "$1" ]]; then
        cd "$1"
        echo "$(pwd -P)"
    else 
        cd "$(dirname "$1")"
        echo "$(pwd -P)/$(basename "$1")"
    fi
}

load_config() {
    config_file="$project_name/.config"
    if [[ ! -f $config_file ]]; then
        echo "Configuration file '$config_file' does not exist. "
        echo "Please initialize the project first using:  'sync.sh init $project_name'"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
    source "$config_file"
}
###### FUNCTIONS #######
init() {
    project_name=${1%/}

    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name as the second argument. Example: sync.sh init my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
    if [[ -d $project_name ]]; then
        echo "Directory '$project_name' already exists. Please choose a different name or remove it before initializing."
        exit 1 || return 1
    fi
    if [[ -f $project_name ]]; then
        echo "File '$project_name' already exists. Please choose a different name or remove it before initializing."
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
    
    echo "You are initializing new directory '$project_name' for remote sychronization:"
    echo
    read -p "REMOTE SSH HOST: [$remote_ssh_host]" -r
    if [[ ! $REPLY =~ ^$ ]]
    then
        remote_ssh_host=$REPLY
    fi
    read -p "REMOTE SSH USER: [$remote_ssh_user]" -r
    if [[ ! $REPLY =~ ^$ ]]
    then
        remote_ssh_user=$REPLY
    fi
    read -p "REMOTE DIRECTORY: [$remote_dir]" -r
    if [[ ! $REPLY =~ ^$ ]]
    then
        remote_dir=$REPLY
    fi
    read -p "REMOTE FILES OWNER [$remote_ssh_user]: " -r
    if [[ $REPLY =~ ^$ ]]
    then
        remote_files_owner=$remote_ssh_user
    else
        remote_files_owner=$REPLY
    fi
    read -p "REMOTE FILES GROUP [$remote_ssh_user]: " -r
    if [[ $REPLY =~ ^$ ]]
    then
        remote_files_group=$remote_ssh_user
    else
        remote_files_group=$REPLY
    fi

    read -p "(OPTIONAL) LOCAL REPOSITORY BASE PATH [$local_repository_base_path]: " -r
    if [[ $REPLY =~ ^$ ]]
    then
        local_repository_base_path=$local_repository_base_path
    else
        local_repository_base_path=$REPLY
    fi

    read -p "(OPTIONAL) LOCAL REPOSITORY DEPLOY PATH [$local_repository_deploy_path]: " -r
    if [[ $REPLY =~ ^$ ]]
    then
        local_repository_deploy_path=$local_repository_deploy_path
    else
        local_repository_deploy_path=$REPLY
    fi

    read -p "(OPTIONAL) LOCAL REPOSITORY BRANCH [$local_repository_branch]: " -r
    if [[ $REPLY =~ ^$ ]]
    then
        local_repository_branch=$local_repository_branch
    else
        local_repository_branch=$REPLY
    fi

    mkdir -p "$project_name/$local_backup_dir"
    # mkdir -p "$project_name/$local_deploy_dir"
    config_file="$project_name/.config"
    echo "# This is your sync.sh project configuration. You can edit this file to change the settings." > "$config_file"
    echo "# Generated automatically by sync.sh on $(date +"%Y%m%d %H%M%S")" >> "$config_file"
    echo >> "$config_file"
    echo "# Remote SSH host (it can be an IP address, a domain name, or a hostname defined in your SSH config)." >> "$config_file"
    echo "remote_ssh_host=$remote_ssh_host" >> "$config_file"
    echo >> "$config_file"
    echo "# Remote SSH user" >> "$config_file"
    echo "remote_ssh_user=$remote_ssh_user" >> "$config_file"
    echo >> "$config_file"
    echo "# Remote rsync directory (note the trailing slash)" >> "$config_file"
    echo "# Full path to the directory on the remote server where you want to sync files." >> "$config_file"
    echo "remote_dir=$remote_dir" >> "$config_file"
    echo >> "$config_file"
    echo "# Remote files ownership settings. Files deployed to the server will be owned by this user." >> "$config_file"
    echo "remote_files_owner=$remote_files_owner" >> "$config_file"
    echo >> "$config_file"
    echo "# Remote files group settings. Files deployed to the server will belong to this group." >> "$config_file"
    echo "remote_files_group=$remote_files_group" >> "$config_file"
    echo >> "$config_file"
    echo "# This is the base path for your local Git repository you want to deploy."
    echo "# It should be path out of the place where this script is located." >> "$config_file"
    echo "local_repository_base_path=$local_repository_base_path" >> "$config_file"
    echo >> "$config_file"
    echo "# This is the path to the directory in your local repository where files to be deployed are located." >> "$config_file"
    echo "# Leave it empty if you want to deploy files from the root of the repository, " >> "$config_file"
    echo "# or set it to a subdirectory if you want to deploy only part of the repository." >> "$config_file"
    echo "# This path is interpreted relative to the preceding local_repository_base_path. " >> "$config_file"
    echo "# For example, if your repository is at /home/user/repo and you want to deploy " >> "$config_file"
    echo "# files from /home/user/repo/dist, set local_repository_base_path to /home/user/repo/ " >> "$config_file"
    echo "# and local_repository_deploy_path to dist/" >> "$config_file"
    echo "local_repository_deploy_path=$local_repository_deploy_path" >> "$config_file"
    echo >> "$config_file"
    echo "# This is the branch in your local repository that you want to deploy." >> "$config_file"
    echo "local_repository_branch=$local_repository_branch" >> "$config_file"
    
    echo "Configuration saved to $config_file"
    echo "Project '$project_name' initialized successfully."
    echo
    echo "You can now download files from the server by running:"
    echo "     $ './sync.sh backup $project_name' "
    echo "New files will be saved in "
    echo "     $project_name/$local_backup_dir"
    echo
    echo "In case you want to edit files locally and then upload them to the server, run:"
    echo "     $ './sync.sh init-deploy $project_name'"
    echo "to prepare working folder "
    echo "     $project_name/$local_deploy_dir"
    echo "then edit files there and when ready, run:"
    echo "     './sync.sh deploy $project_name'  to upload files to the server."
    echo 
    echo "If you want to deploy files from a local Git repository, you can run:"
    echo "     $ './sync.sh git-deploy $project_name' "
    echo "This will copy files from the specified $local_repository_branch branch of:"
    echo "     git: $local_repository_base_path"
    echo "and place them in the local deploy directory:"
    echo "     $project_name/$local_deploy_dir"
    echo "Use then:"
    echo "     './sync.sh deploy $project_name'  to upload files to the server."
    echo
    echo "You can also add extra rsync options to the backup and deploy commands."
    echo "For example, to delete files on the server that are not in the local deploy directory, you can run:"
    echo "     $ './sync.sh deploy $project_name --delete' "
    echo
}
backup-deploy() {
    project_name=${1%/}    
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh init-deploy my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    load_config

    echo
    echo "****** RSYNC *** (backup -> deploy) ***"
    echo rsync -avz \
        "$project_name/$local_backup_dir" \
        "$project_name/$local_deploy_dir"
    echo "********************"
    echo
    if [[ -d "$project_name/$local_deploy_dir" ]]; then 
        echo "Directory '$project_name/$local_deploy_dir' already exists."
        echo "Files with the same name will be overwritten with files from '$project_name/$local_backup_dir'?"
        echo 
        read -p "Continue? [yes/NO]: " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
        then
            echo "Cancelled"
            exit 1 || return 1
        fi
    fi

    rsync -avz \
        "$project_name/$local_backup_dir" \
        "$project_name/$local_deploy_dir"

    # cp -a "$project_name/$local_backup_dir" "$project_name/$local_deploy_dir" 
    echo "Done!"  
}

backup() {

    project_name=${1%/}    
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh backup my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    load_config

    echo "Download files: "
    echo
    echo "            SRC: $remote_ssh_host:$remote_dir"
    echo "   ___<<<___/ "
    echo "  / "
    echo "DEST: $project_name/$local_backup_dir"
    echo 

    if [[ -n "$8" ]]; then
        echo "Too many arguments. Please provide up to 6 extra arguments for rsync options."
        echo "Example:  sync.sh backup my_project --delete --exclude=cache/"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    echo "****** RSYNC **** (server -> backup) ***"
    echo rsync -avz -og \
        -e ssh \
        --partial \
        --exclude=.git \
        --info=progress3,stats0 \
        $2 \
        $3 \
        $4 \
        $5 \
        $6 \
        $7 \
        $remote_ssh_user@$remote_ssh_host:$remote_dir \
        $project_name/$local_backup_dir
    echo "********************"
    echo
    read -p "Updating local directory... Continue? [yes/NO]: " -r
    echo 
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
    then
        [[ "$0" = "$BASH_SOURCE" ]] && \
        echo "Cancelled" && \
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    rsync -avz -og \
        -e ssh  \
        --partial \
        --exclude=.git \
        --info=progress3,stats0 \
        $2 \
        $3 \
        $4 \
        $5 \
        $6 \
        $7 \
        $remote_ssh_user@$remote_ssh_host:$remote_dir  \
        $project_name/$local_backup_dir
}

deploy() {
    project_name=${1%/}
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh deploy my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    load_config

    if [[ ! -d "$project_name/$local_deploy_dir" ]]; then 
        echo "Project '$project_name' is initialized for backup (downloading files) only and"
        echo "does not have a local deploy directory. Please initialize the project for deploying"
        echo "functionality by command:"
        echo "    $ sync.sh init-deploy $project_name"
        echo "or copy files you want into "
        echo "    $project_name/$local_deploy_dir"
        echo "and try again."
        exit 1 || return 1
    fi

    echo -e "Upload data:"
    echo    
    echo "SRC: $project_name/$local_deploy_dir"
    echo "  \___>>>___"
    echo "            \ "       
    echo "           DEST: $remote_ssh_host:$remote_dir"
    echo

    if [[ -n "$8" ]]; then
        echo "Too many arguments. Please provide up to 6 extra arguments for rsync options."
        echo "Example:  sync.sh backup my_project --delete --exclude=cache/"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi


#     echo rsync -avz \
        # --chown=$remote_files_owner:$remote_files_group \
    echo "****** RSYNC **** (deploy -> server) ***"
    echo rsync -avz \
        --chown=$remote_files_owner:$remote_files_group \
        -e ssh \
        --partial \
        --exclude=.git \
        --info=progress3,stats0 \
        $2 \
        $3 \
        $4 \
        $5 \
        $6 \
        $7 \
        $project_name/$local_deploy_dir \
        $remote_ssh_user@$remote_ssh_host:$remote_dir
    echo "********************"
    echo
    read -p "Updating server directory... Continue? [yes/NO]: " -r
    echo 
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
    then
        [[ "$0" = "$BASH_SOURCE" ]] && \
        echo "Cancelled" && \
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    if [[ -n "$8" ]]; then
        echo "Too many arguments. Please provide up to 6 extra arguments for rsync options."
        echo "Example:  sync.sh deploy my_project --delete --exclude=.*//"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi


    rsync -avz \
        --chown=$remote_files_owner:$remote_files_group \
        -e ssh \
        --partial \
        --exclude=.git \
        --info=progress3,stats0 \
        $2 \
        $3 \
        $4 \
        $5 \
        $6 \
        $7 \
        $project_name/$local_deploy_dir \
        $remote_ssh_user@$remote_ssh_host:$remote_dir
}

git-deploy() {
    project_name=${1%/}
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh git-deploy my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    load_config

    if [[ ! -d "${local_repository_base_path%/}/.git" ]]; then 
        echo "The specified local repository path '$local_repository_base_path' is not a valid Git repository."
        echo "Please check the path and try again."
        exit 1 || return 1
    fi

    echo "Checking out branch '$local_repository_branch' in local repository at '$local_repository_base_path'."
    echo git -C "$local_repository_base_path" checkout "$local_repository_branch"
    git -C "$local_repository_base_path" checkout "$local_repository_branch" > /dev/null 2>&1
    echo
    echo "****** RSYNC *** (repo -> deploy) ***"
    echo rsync -avz \
        --exclude=".*" \
        "$local_repository_base_path$local_repository_deploy_path" \
        "$project_name/$local_deploy_dir"
    echo "********************"
    echo
    read -p "Copying files from local repository... Continue? [yes/NO]: " -r
    echo 
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
    then
        [[ "$0" = "$BASH_SOURCE" ]] && \
        echo "Cancelled" && \
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    rsync -avz \
        --exclude=".*" \
        "$local_repository_base_path$local_repository_deploy_path" \
        "$project_name/$local_deploy_dir"

    echo "Done. You can now run 'sync.sh deploy $project_name' to upload files to the server."
}

rotate() {
    project_name=${1%/}
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh backup my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi

    load_config

    timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "$project_name/$local_rotate_dir$timestamp/$local_backup_dir"
    cp -a "$project_name/$local_backup_dir" "$project_name/$local_rotate_dir$timestamp/"
    echo "Backup rotated: $project_name/$local_rotate_dir$timestamp/$local_backup_dir"
    if [[ -d "$project_name/$local_deploy_dir" ]]; then 
        mkdir -p "$project_name/$local_rotate_dir$timestamp/$local_deploy_dir"
        cp -a "$project_name/$local_deploy_dir" "$project_name/$local_rotate_dir$timestamp/"
        echo "Backup rotated: $project_name/$local_rotate_dir$timestamp/$local_deploy_dir"
    fi
}
status() {
    project_name=${1%/}
    if [[ ! -n "$project_name" ]]; then
        echo "Please provide a project name. Example: sync.sh status my_project"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
    load_config

    echo "STATUS: $project_name"
    echo
    echo " Local computer:"

    echo "  \_ backup  (files pulled from server):"
    if [[ -d "$project_name/$local_backup_dir" ]]; then
         echo "       $(full_path "$project_name/$local_backup_dir") "
    else
         echo "       NOT INITIALIZED"
    fi
    echo
    echo "  \_ deploy  (filles that will be pushed to server):"
    if [[ -d "$project_name/$local_deploy_dir" ]]; then
         echo "       $(full_path "$project_name/$local_deploy_dir") "
    else
         echo "       NOT INITIALIZED"
    fi
    echo
    echo "  \_ rotate  (snapshots of backup and deploy directories):"
    if [[ -d "$project_name/$local_deploy_dir" ]]; then
         echo "       $(full_path "$project_name/$local_rotate_dir") "
    else
         echo "       NONE"
    fi
    echo
    echo
    echo " Remote server:"
    echo "  SSH HOST:      $remote_ssh_host"
    echo "  SSH USER:      $remote_ssh_user"
    echo "  DIR:           $remote_dir"
    echo "    \_ chown (owner):  $remote_files_owner"
    echo "    \_ chgrp (group):  $remote_files_group"
    echo
    echo 

    echo "               T..G..M..K..B.."
    if [[ -d "$project_name/$local_backup_dir" ]]; then 
        cd "$project_name/$local_backup_dir"
        backup_dir_length=$(du -hsb . \
            | cut -f1)
        cd "../.."
        printf "backup dir:   %16s bytes\n" "$backup_dir_length"
    else 
        printf "backup dir:   %16s\n" "-"
    fi

    if [[ -d "$project_name/$local_deploy_dir" ]]; then
        cd "$project_name/$local_deploy_dir"
        deploy_dir_length=$(du -hsb . \
            | cut -f1)
        cd "../.."
        printf "deploy dir:   %16s bytes\n" "$deploy_dir_length"
    else
        printf "deploy dir:   %16s\n" "-"
    fi

    if [[ -d "$project_name/$local_rotate_dir" ]]; then
        cd "$project_name/$local_rotate_dir"
        rotate_dir_length=$(du -hsb . \
            | cut -f1)
        cd "../.."
        printf "rotate dir:   %16s bytes\n" "$rotate_dir_length"
    else
        printf "rotate dir:   %16s\n" "-"
    fi

    if [[ -d "$project_name/$local_backup_dir" ]]; then 
        cd "$project_name/$local_backup_dir"
        backup_digest=$(find . \
            -type f \
            -exec sha256sum {} + \
            | LC_ALL=C sort \
            | sha256sum)
        backup_digest=${backup_digest%% *}
        cd "../.."
        echo "backup SHA2: $backup_digest" 
    else 
        echo "backup SHA2: -"
    fi

    if [[ -d "$project_name/$local_deploy_dir" ]]; then
        cd "$project_name/$local_deploy_dir"
        deploy_digest=$(find . \
            -type f \
            -exec sha256sum {} + \
            | LC_ALL=C sort \
            | sha256sum)
        deploy_digest=${deploy_digest%% *}
        cd "../.."
        echo "deploy SHA2: $deploy_digest"
    else
        echo "deploy SHA2: -"
    fi
}

help-script() {
    echo "Usage: sync.sh [ { init | init-deploy | backup | deploy } <dir> | help ]"
    echo
    echo "  sync.sh  help                - show this help message"
    echo "  sync.sh  init  <dir>         - initialize new project with given name,"
    echo "  sync.sh  backup <dir> [args] - download files from server to local directory;"
    echo "                                 (backup); pass optional args for rsync"
    echo "  sync.sh  backup-deploy <dir> - copy backup files into deploy directory;"
    echo "  sync.sh  deploy <dir> [args] - upload files from local directory to server;"
    echo "                                 (deploy); pass optional args for rsync" 
    echo "  sync.sh  git-deploy          - copy git repository files into deploy directory"
    echo "                                 (will overwrite existing ones);"
    echo "  sync.sh  clone <dir>         - init + init-deploy equivalent;"
    echo "  sync.sh  rotate <dir>        - make project copy (both backup and deploy directories)"
    echo "  sync.sh  status  <dir>       - show project info and settings"
    echo "  sync.sh  update              - update this script to the latest version"
    echo "  sync.sh  version             - show script version"
    echo 
    echo "DESCRIPTION:"
    echo "  This script is a wrapper around rsync and SSH for synchronizing files"
    echo "between a local directory and a remote server."
    echo 
    echo "SETUP:"
    echo "  To set up a new project, run 'sync.sh init <project_name>'. This will create"
    echo "a new directory with the given name and a configuration file inside it. Now you,"
    echo "can download files from specific server. If you want edit files locally and then"
    echo "upload them to the server, you have to run 'sync.sh backup-deploy <project_name>'"
    echo "after initializing the project. This will create a local deploy directory where"
    echo "you can edit files before deploying them to the server."
    echo 
    echo "WARNING:"
    echo "  Use this script responsibly and make sure you have backups of your data"
    echo "before deploying changes to the server."
    echo
    echo "  Dariusz Chilimoniuk, https://stack.pl , https://github.com/stack-pl/sync "
    echo
}
###### MAIN LOGIC ######

case "${1:-}" in
    backup)
        backup $2 $3 $4 $5 $6 $7 $8 $9
        ;;
    backup-deploy)
        backup-deploy $2
        ;;   
    clone)
        init $2
        backup $2 $3 $4 $5 $6 $7 $8 $9
        backup-deploy $2
        rotate $2
        status $2
        ;;
    deploy)
        deploy $2 $3 $4 $5 $6 $7 $8 $9
        ;;
    git-deploy)
        git-deploy $2
        ;; 
    help)
        help-script
        ;;
    init)
        init $2
        ;;
    rotate)
        rotate $2
        ;;
    status)
        status $2
         ;;
    update)
        update_script
        ;;
    version)
        print_version
        ;;
    *)
        echo "sync.sh is rsync+ssh wrapper for file synchronization."
        echo
        echo "Run  'sync.sh help'  for usage instructions"
        echo
        ;;
esac
