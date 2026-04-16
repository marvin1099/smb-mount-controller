#!/bin/bash

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_BASE="https://codeberg.org/marvin1099/smb-mount-controller/raw/branch/main"

SCRIPT_URL="$REPO_BASE/smb-controller.sh"
CONF_URL="$REPO_BASE/example-smb-controller.conf"
SERVICE_URL="$REPO_BASE/default-smb-controller.service"

INSTALL_PATH="/usr/local/bin/smb-controller"
CONF_PATH="/etc/smb-controller.conf"
SERVICE_PATH="/etc/systemd/system/smb-controller.service"

TMP_DIR="/tmp/smb-controller-install"

mkdir -p "$TMP_DIR"

INSTALL_NOW=0
REMOVE_NOW=0
LOCAL_MODE=0
NO_SYSTEMD=0
READ_SCRIPT=0
SYSTEMD_ACTIVATE=0
CONFIG_EDIT=0

show_help() {
  cat << EOF
SMB Mount Controller Installer

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
  -h          Show this help message and exit
  -k          To run interactive installer
              (or run without arguments)
  -i          Install non-interactively
  -r, -u      Uninstall non-interactively
  -l          Local mode: use files from script directory instead of downloading
              (use with -i or via interactive installer to install from local files)
  -n          No systemd: skip systemd service file creation/deletion
              (use with -i or -r/-u)
  -s          To read the script before installing
              (uses command less, use with -i or -r/-u)
  -a          To activate and start the systemd service
              (use with -i and without -n)
  -c          To edit the config in non interactive mode
              (use with -i, disables opening the config in interactive mode)

EXAMPLES:
  $(basename "$0")           # Interactive installer
  $(basename "$0") -i        # Install non-interactively
  $(basename "$0") -i -l     # Install using local files
  $(basename "$0") -i -n     # Install without systemd service
  $(basename "$0") -i -a     # Install and enable systemd service
  $(basename "$0") -i -c     # Install and edit config
  $(basename "$0") -i -l -n  # Local install without systemd
  $(basename "$0") -i -l -a  # Local install with systemd activation
  $(basename "$0") -r        # Uninstall
  $(basename "$0") -r -n     # Uninstall without systemd
  $(basename "$0") -u        # Uninstall (alias)

EOF
  exit 0
}

while getopts "hirulnsakc" opt; do
  case "$opt" in
    h)
      show_help
      ;;
    i)
      INSTALL_NOW=1
      ;;
    r|u)
      REMOVE_NOW=1
      ;;
    l)
      LOCAL_MODE=1
      ;;
    n)
      NO_SYSTEMD=1
      ;;
    s)
      READ_SCRIPT=1
      ;;
    a)
      SYSTEMD_ACTIVATE=1
      ;;
    c)
      CONFIG_EDIT=1
      ;;
    k)
      : # -k is the same as no argument so just shallow it
      ;;
    \?)
      echo "Use -h for help"
      exit 1
      ;;
  esac
done


# =========================
# ROOT / SUDO HANDLING
# =========================

IS_ROOT=0

if [[ "$EUID" -eq 0 ]]; then
  IS_ROOT=1
fi

sudo_cmd() {
  if (( IS_ROOT )); then
    "$@"
  else
    sudo "$@"
  fi
}

keep_sudo_alive() {
  if (( ! IS_ROOT )); then
    while true; do
      sudo -n true 2>/dev/null || break
      sleep 60
    done &
    SUDO_KEEPALIVE_PID=$!
  fi
}

stop_sudo_alive() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
}

cleanup() {
  stop_sudo_alive
  exit 0
}

trap cleanup EXIT INT TERM

unlock_sudo() {
  if (( ! IS_ROOT )); then
    if (( INSTALL_NOW )) || (( REMOVE_NOW )); then
      keep=n
    else
      read -rp "Keep sudo alive during install? (recommended for long installs) (y/N): " keep
    fi
    sudo -v || {
      echo "Can't continue without superuser";
      exit 1
    }
    if [[ "$keep" == "y" ]]; then
      keep_sudo_alive
    fi
  fi
}


# =========================
# UTIL
# =========================
download() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" ]]; then
    sudo_cmd rm "$out"
  fi

  if (( LOCAL_MODE )); then
    local filename
    filename=$(basename "$url")
    if [[ -f "$SCRIPT_DIR/$filename" ]]; then
      cp "$SCRIPT_DIR/$filename" "$out"
      return 0
    else
      echo "ERROR: Local file $SCRIPT_DIR/$filename not found"
      return 1
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$out"
  else
    echo "ERROR: curl or wget required"
    exit 1
  fi
}

# =========================
# MENU SYSTEM
# =========================
menu_select() {
  local title="$1"
  shift
  local options=("$@")

  while true; do
    echo
    echo "=== $title ==="
    echo

    for i in "${!options[@]}"; do
      printf "%d) %s\n" "$((i+1))" "${options[$i]}"
    done

    echo
    read -rp "Select option: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      return $((choice-1))
    else
      echo "Invalid option"
    fi
  done
}

# =========================
# UNINSTALL
# =========================
do_uninstall() {
  echo "Uninstalling..."
  unlock_sudo

  if (( ! NO_SYSTEMD )); then
    sudo_cmd systemctl stop smb-controller 2>/dev/null
    sudo_cmd systemctl disable smb-controller 2>/dev/null
    sudo_cmd rm -f "$SERVICE_PATH"
  else
    echo "Skipping systemd service removal, because of no systemd"
  fi

  sudo_cmd rm -f "$INSTALL_PATH"

  echo "Done."
  exit 0
}

# =========================
# INSTALL SCRIPT
# =========================
install_script() {
  echo "Downloading controller..."

  download "$SCRIPT_URL" "$TMP_DIR/smb-controller.sh" || {
    echo "Failed to grab script"
    exit 1
  }

  sudo_cmd install -m 755 "$TMP_DIR/smb-controller.sh" "$INSTALL_PATH"
  echo "Installed to $INSTALL_PATH"
}

# =========================
# CONFIG SETUP
# =========================
setup_config() {
  if (( INSTALL_NOW )); then
    selected=0
  else
    menu_select "Config setup" \
      "Keep old config or copy example config (recommended)" \
      "Keep old config or create empty config" \
      "Copy example config and override"\
      "Create empty config"
    selected=$?
  fi

  case $selected in
    0)
      if [[ ! -f "$CONF_PATH" ]]; then
        download "$CONF_URL" "$TMP_DIR/smb-controller.conf" || {
          echo "Failed to grab config"
          exit 1
        }
        sudo_cmd mv "$TMP_DIR/smb-controller.conf" "$CONF_PATH"
      fi
      ;;
    1)
      sudo_cmd touch "$CONF_PATH"
      ;;
    2)
      download "$CONF_URL" "$TMP_DIR/smb-controller.conf" || {
        echo "Failed to grab config"
        exit 1
      }
      sudo_cmd mv "$TMP_DIR/smb-controller.conf" "$CONF_PATH"
      ;;
    3)
      sudo_cmd rm "$CONF_PATH"
      sudo_cmd touch "$CONF_PATH"
      ;;
  esac

  sudo_cmd chmod 644 "$CONF_PATH"

  echo "Config file placed at: $CONF_PATH"
  if (( INSTALL_NOW )) && ! (( CONFIG_EDIT )); then
    echo "Config file edit skipped, because of install now"
    return 0
  elif (( CONFIG_EDIT )) && ! (( INSTALL_NOW )); then
    echo "Config file edit skipped, because of config edit in interactive mode"
    return 0
  fi
  echo "Opening config for editing..."
  sudo_cmd ${EDITOR:-nano} "$CONF_PATH" || ${EDITOR:-nano} "$CONF_PATH"
}

# =========================
# SYSTEMD SETUP
# =========================
setup_systemd() {
  if (( NO_SYSTEMD )); then
    echo "Skipping systemd service setup, because of no systemd"
    return 0
  fi

  local choice
  if (( INSTALL_NOW )); then
    if (( SYSTEMD_ACTIVATE )); then
      echo "Enabling systemd now, because of systemd activate"
      choice=1
    else
      echo "Downloading service file only, because of install now"
      echo "Enable with: systemctl enable --now smb-controller"
      choice=3
    fi
  else
    menu_select "Systemd setup (smb-controller.service)" \
      "Yes, enable and start now" \
      "Yes, enable only" \
      "Yes, start only" \
      "Yes, just install service file" \
      "No, but run controller now" \
      "No, end installer"
    choice=$?
  fi



  if (( choice <= 3 )); then
    download "$SERVICE_URL" "$TMP_DIR/smb-controller.service" || {
      echo "Failed to grab service"
      exit 1
    }

    sudo_cmd mv "$TMP_DIR/smb-controller.service" "$SERVICE_PATH"
    echo "Placing service file at $SERVICE_PATH"
    sudo_cmd systemctl daemon-reexec
    sudo_cmd systemctl daemon-reload
  fi

  case $choice in
    0)
      sudo_cmd systemctl enable --now smb-controller
      ;;
    1)
      sudo_cmd systemctl enable smb-controller
      ;;
    2)
      sudo_cmd systemctl start smb-controller
      ;;
    4)
      echo "Starting controller manually..."
      sudo_cmd "$INSTALL_PATH"
      ;;
  esac
}

# =========================
# MAIN MENU
# =========================
main_menu() {
  if (( INSTALL_NOW )); then
    if (( READ_SCRIPT )); then
      less "$0"
    fi
    return 0
  elif (( REMOVE_NOW )); then
    if (( READ_SCRIPT )); then
      less "$0"
    fi
    do_uninstall
  fi
  while true; do
    menu_select "SMB Mount Controller Installer" \
      "Read installer script" \
      "Install" \
      "Uninstall" \
      "Cancel"

    case $? in
      0)
        less "$0"
        ;;
      1)
        return 0
        ;;
      2)
        do_uninstall
        ;;
      3)
        echo "Cancelled."
        exit 0
        ;;
    esac
  done
}

# =========================
# MAIN FLOW
# =========================
main() {
  main_menu
  unlock_sudo
  install_script
  echo
  setup_config
  echo
  setup_systemd

  echo
  echo "Installation complete!"
}

main
