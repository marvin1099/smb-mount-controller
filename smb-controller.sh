#!/bin/bash

set +e

CONFIG_FILE="/etc/smb-controller.conf"

# =========================
# LOAD CONFIG
# =========================
[[ ! -f "$CONFIG_FILE" ]] && echo "ERROR: Missing config $CONFIG_FILE" && exit 1
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# =========================
# VALIDATION
# =========================
[[ -z "$MOUNT_OPTIONS" ]] && echo "ERROR: MOUNT_OPTIONS not set" && exit 1
[[ ${#SERVERS[@]} -eq 0 ]] && echo "ERROR: SERVERS empty" && exit 1
[[ ${#PATHS[@]} -eq 0 ]] && echo "ERROR: PATHS empty" && exit 1

# =========================
# VALIDATION WITH DEFAULTS
# =========================
[[ -z "$SPAWN_DELAY" ]] && SPAWN_DELAY=0.1
[[ -z "$SERVER_DELAY" ]] && SERVER_DELAY=0.1
[[ -z "$COUNT_MAX" ]] && COUNT_MAX=3
[[ -z "$SLEEP" ]] && SLEEP=5
[[ -z "$CHECK_TIMEOUT" ]] && CHECK_TIMEOUT=1

# =========================
# STATE
# =========================
declare -A ONLINE_COUNT
declare -A OFFLINE_COUNT

# =========================
# INIT STATE
# =========================
init_state() {
  for srv in "${SERVERS[@]}"; do
    IFS=":" read -r NAME IP CREDS <<< "$srv"

    ONLINE_COUNT["$NAME"]=0
    OFFLINE_COUNT["$NAME"]=0
  done
}

# =========================
# NETWORK CHECK
# =========================
check_online() {
  local ip="$1"
  timeout "$CHECK_TIMEOUT" nc -z -w1 "$ip" 445 >/dev/null 2>&1
}

# =========================
# MOUNT HANDLER
# =========================
handle_mounts() {
  local NAME="$1" IP="$2" CREDS="$3"

  for p in "${PATHS[@]}"; do
    (
      IFS=":" read -r label mnt remote target <<< "$p"
      [[ "$target" != "$NAME" ]] && exit 0

      mkdir -p "$mnt"

      if ! findmnt -rno TARGET "$mnt" >/dev/null 2>&1; then
        echo "[SMB-$NAME] Mounting $label"

        if mount -t cifs "//$IP$remote" "$mnt" \
          -o "$MOUNT_OPTIONS,credentials=$CREDS"; then
          echo "[SMB-$NAME] SUCCESS: $mnt"
        else
          echo "[SMB-$NAME] FAILED: $mnt"
        fi
      fi
    ) &
    sleep "$SPAWN_DELAY"
  done

  wait
}

# =========================
# UNMOUNT HANDLER
# =========================
handle_unmounts() {
  local NAME="$1"

  for p in "${PATHS[@]}"; do
    (
      IFS=":" read -r label mnt remote target <<< "$p"
      [[ "$target" != "$NAME" ]] && exit 0

      if findmnt -rno TARGET "$mnt" >/dev/null 2>&1; then
        echo "[SMB-$NAME] Unmounting $label"

        if umount -l "$mnt" 2>/dev/null; then
          echo "[SMB-$NAME] SUCCESS: $mnt"
        else
          echo "[SMB-$NAME] FAILED: $mnt"
        fi
      fi
    ) &
    sleep "$SPAWN_DELAY"
  done

  wait
}

# =========================
# SERVER LOOP
# =========================
handle_server() {
  local srv="$1"

  IFS=":" read -r NAME IP CREDS <<< "$srv"

  if check_online "$IP"; then

    OFFLINE_COUNT["$NAME"]=0

    if (( ONLINE_COUNT["$NAME"] < COUNT_MAX )); then
      ((ONLINE_COUNT["$NAME"]++))
      echo "[SMB-$NAME] ONLINE ${ONLINE_COUNT[$NAME]}/$COUNT_MAX"
      handle_mounts "$NAME" "$IP" "$CREDS" &
      sleep "$SERVER_DELAY"
    fi

  else

    ONLINE_COUNT["$NAME"]=0

    if (( OFFLINE_COUNT["$NAME"] < COUNT_MAX )); then
      ((OFFLINE_COUNT["$NAME"]++))
      echo "[SMB-$NAME] OFFLINE ${OFFLINE_COUNT[$NAME]}/$COUNT_MAX"
      handle_unmounts "$NAME" &
      sleep "$SERVER_DELAY"
    fi

  fi
}

# =========================
# MAIN
# =========================
init_state

while true; do

  for srv in "${SERVERS[@]}"; do
    handle_server "$srv"
  done

  wait
  sleep "$SLEEP"
done
