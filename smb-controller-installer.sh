#!/bin/bash

set +e

REPO_BASE="https://codeberg.org/marvin1099/smb-mount-controller/raw/branch/main"

SCRIPT_URL="$REPO_BASE/smb-controller.sh"
CONF_URL="$REPO_BASE/example-smb-controller.conf"
SERVICE_URL="$REPO_BASE/default-smb-controller.service"

INSTALL_PATH="/usr/local/bin/smb-controller"
CONF_PATH="/etc/smb-controller.conf"
SERVICE_PATH="/etc/systemd/system/smb-controller.service"

TMP_DIR="/tmp/smb-controller-install"

mkdir -p "$TMP_DIR"


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
    read -rp "Keep sudo alive during install? (recommended for long installs) (y/N): " keep
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

  sudo_cmd systemctl stop smb-controller 2>/dev/null
  sudo_cmd systemctl disable smb-controller 2>/dev/null

  sudo_cmd rm -f "$INSTALL_PATH"
  sudo_cmd rm -f "$SERVICE_PATH"

  echo "Done."
  exit 0
}

# =========================
# INSTALL SCRIPT
# =========================
install_script() {
  echo "Downloading controller..."

  download "$SCRIPT_URL" "$TMP_DIR/smb-controller.sh" || {
    echo "Failed to download script"
    exit 1
  }

  sudo_cmd install -m 755 "$TMP_DIR/smb-controller.sh" "$INSTALL_PATH"
  echo "Installed to $INSTALL_PATH"
}

# =========================
# CONFIG SETUP
# =========================
setup_config() {
  menu_select "Config setup" \
    "Copy example config (recommended)" \
    "Create empty config"

  case $? in
    0)
      download "$CONF_URL" "$TMP_DIR/smb-controller.conf" || {
        echo "Failed to download config"
        exit 1
      }
      sudo_cmd mv "$TMP_DIR/smb-controller.conf" "$CONF_PATH"
      ;;
    1)
      sudo_cmd touch "$CONF_PATH"
      ;;
  esac

  sudo_cmd chmod 600 "$CONF_PATH"

  echo
  echo "Opening config for editing..."
  sudo_cmd ${EDITOR:-nano} "$CONF_PATH" || ${EDITOR:-nano} "$CONF_PATH"
}

# =========================
# SYSTEMD SETUP
# =========================
setup_systemd() {
  menu_select "Systemd setup (smb-controller.service)" \
    "Yes, enable and start now" \
    "Yes, enable only" \
    "Yes, start only" \
    "Yes, just install service file" \
    "No, but run controller now" \
    "No, end installer"

  local choice=$?

  if (( choice <= 3 )); then
    download "$SERVICE_URL" "$TMP_DIR/smb-controller.service" || {
      echo "Failed to download service"
      exit 1
    }

    sudo_cmd mv "$TMP_DIR/smb-controller.service" "$SERVICE_PATH"
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
    5)
      echo "Starting controller manually..."
      sudo_cmd "$INSTALL_PATH"
      ;;
  esac
}

# =========================
# MAIN MENU
# =========================
main_menu() {
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
  setup_config
  setup_systemd

  echo
  echo "Installation complete!"
}

main