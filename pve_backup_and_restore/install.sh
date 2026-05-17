#!/bin/bash
# Installer for prox_config_backup.sh
# Clones / updates the repository, configures the backup directory,
# and sets up a monthly cron job.

set -e

REPO_URL="https://github.com/DerDanilo/proxmox-stuff"
INSTALL_DIR="/root/proxmox-stuff"
SCRIPT_DIR="$INSTALL_DIR/pve_backup_and_restore"
CRON_FILE="/etc/cron.monthly/proxmox-config-backup"

# --- disclaimer ---

show_disclaimer() {
    cat <<'EOF'

========================================================================
  DISCLAIMER — READ CAREFULLY BEFORE PROCEEDING
========================================================================

  This installer and the associated scripts are provided AS-IS, without
  any warranty of any kind, express or implied, including but not limited
  to warranties of merchantability, fitness for a particular purpose, or
  non-infringement.

  - This software has been tested only in limited, specific environments.
    It may not work correctly in yours.
  - Running this installer will clone a repository to your system, modify
    cron jobs, and potentially create directories with root privileges.
  - The backup and restore scripts touch critical system files. Incorrect
    use WILL break your Proxmox installation.
  - The author accepts NO responsibility for data loss, downtime, broken
    systems, or any other damage — direct or indirect — resulting from the
    use of this software.

  USE AT YOUR OWN RISK.

  If you do not agree, press Ctrl+C now.

  To continue, type  AGREE  and press Enter:
EOF

    read -rp "  > " DISCLAIMER_INPUT
    if [[ "$DISCLAIMER_INPUT" != "AGREE" ]]; then
        echo
        echo "Aborted. You must type AGREE to proceed."
        exit 1
    fi
    echo
}

# --- helpers ---

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
abort() { echo "[ERROR] $*" >&2; exit 1; }

check_root() {
    [[ ${EUID} -eq 0 ]] || abort "This installer must be run as root."
}

check_dependencies() {
    for cmd in git curl; do
        command -v "$cmd" &>/dev/null || abort "'$cmd' is required but not installed."
    done
}

clone_or_update() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        info "Existing installation found at $INSTALL_DIR — updating..."
        git -C "$INSTALL_DIR" pull --ff-only
    else
        info "Cloning repository to $INSTALL_DIR ..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
    chmod +x "$SCRIPT_DIR/prox_config_backup.sh"
    chmod +x "$SCRIPT_DIR/prox_config_restore.sh"
    info "Scripts are executable."
}

configure_backup_dir() {
    local default="/mnt/pve/media/backup"
    echo
    echo "Where should backups be stored?"
    echo "  Default: $default"
    read -rp "  Backup directory [${default}]: " BACK_DIR
    BACK_DIR="${BACK_DIR:-$default}"

    if [[ ! -d "$BACK_DIR" ]]; then
        warn "Directory '$BACK_DIR' does not exist."
        read -rp "  Create it now? [y/N]: " CREATE_DIR
        if [[ "$CREATE_DIR" =~ ^[yY]$ ]]; then
            mkdir -p "$BACK_DIR"
            info "Created $BACK_DIR"
        else
            warn "Backup directory not created. You must create it before running the backup."
        fi
    fi
}

configure_max_backups() {
    local default=5
    echo
    read -rp "How many backups to keep? [${default}]: " MAX_BACKUPS
    MAX_BACKUPS="${MAX_BACKUPS:-$default}"
    if ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] || [[ "$MAX_BACKUPS" -lt 1 ]]; then
        warn "Invalid value, falling back to $default."
        MAX_BACKUPS=$default
    fi
}

setup_cron() {
    echo
    read -rp "Set up a monthly cron job for automatic backups? [Y/n]: " SETUP_CRON
    SETUP_CRON="${SETUP_CRON:-y}"
    if [[ "$SETUP_CRON" =~ ^[nN]$ ]]; then
        info "Skipping cron setup."
        return
    fi

    cat > "$CRON_FILE" <<EOF
#!/bin/bash
# Proxmox config backup — installed by install.sh
BACK_DIR="${BACK_DIR}" MAX_BACKUPS=${MAX_BACKUPS} "${SCRIPT_DIR}/prox_config_backup.sh"
EOF
    chmod +x "$CRON_FILE"
    info "Cron job written to $CRON_FILE"
    info "Test with: run-parts -v --test /etc/cron.monthly"
}

print_summary() {
    echo
    echo "================================================================"
    echo " Installation complete"
    echo "================================================================"
    echo " Scripts   : $SCRIPT_DIR"
    echo " Backup to : $BACK_DIR"
    echo " Keep      : $MAX_BACKUPS backups"
    if [[ -f "$CRON_FILE" ]]; then
        echo " Cron job  : $CRON_FILE"
    fi
    echo
    echo " Run manually:"
    echo "   $SCRIPT_DIR/prox_config_backup.sh"
    echo
    echo " Restore:"
    echo "   $SCRIPT_DIR/prox_config_restore.sh <backup-file.tar.gz>"
    echo "================================================================"
}

# --- main ---

show_disclaimer
check_root
check_dependencies
clone_or_update
configure_backup_dir
configure_max_backups
setup_cron
print_summary
