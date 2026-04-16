# smb-mount-controller

A state-based SMB/CIFS mount controller for Linux that manages network shares based on reachability.  
It is designed to prevent desktop freezes, reduce mount instability, and provide predictable control over SMB mounts across multiple servers.

AI was use a lot here, I'm mostly just sharing this because I like it myself.

---

## Overview

This tool replaces traditional automount approaches (such as autofs in desktop environments) with a deterministic state system:

- Shares are mounted only after the server is confirmed online (up to 3 trys by default)
- Shares are unmounted only after the server is confirmed offline (up to 3 trys by default)
- Supports multiple SMB servers in parallel
- Designed for use with systemd (but can be easly replaced, it just needs to run in root on startup)

---

## Features

- Multi-server SMB/CIFS support
- Parallel mount and unmount execution
- Stateful online/offline detection using counters
- Configurable retry thresholds
- Lazy unmount to avoid "device busy" issues
- Optional staggered execution delays (by default 0.1 seconds)
- Does not interfere after stabilization (hands control back to user)
- Systemd integration included (can be skipped)
- Non-blocking design to avoid file manager freezes

---

## How it works

Each server is monitored independently.

### Online detection
- If the server responds on port 445, an ONLINE counter increases
- All configured shares for that server are mounted
- If mount succeeds, the counter continues counting up until COUNT_MAX is reached, then stops trying (allows manual control)
- If mount fails, it will retry up to COUNT_MAX times

### Offline detection
- If the server is unreachable, an OFFLINE counter increases
- All shares are unmounted using lazy unmount
- If unmount succeeds, the counter continues counting up until COUNT_MAX is reached, then stops trying (allows manual control)
- If unmount fails, it will retry up to COUNT_MAX times

After either action completes, the system stops acting until state changes again.

---

## Quick start

Paste the following in a terminal and press enter

```bash
bash -c '
curl -fsSL https://codeberg.org/marvin1099/smb-mount-controller/raw/branch/main/smb-controller-installer.sh -o smb-controller-installer.sh \
|| { echo "Download failed"; exit 1; }
chmod +x smb-controller-installer.sh || { echo "chmod failed"; exit 1; }
echo "Downloaded to $(realpath smb-controller-installer.sh)"

IFS= read -rp "Read installer? (y/n) " ans; ans=${ans,,}
[[ "$ans" == y* ]] && less smb-controller-installer.sh
IFS= read -rp "Keep installer on exit? (y/n) " anw; anw=${anw,,}
IFS= read -rp "Run installer? (y/n) " ans; ans=${ans,,}
[[ "$ans" == y* ]] && ./smb-controller-installer.sh || NO=1

[[ "$anw" == y* ]] && echo "Keeping installer" \
|| { rm ./smb-controller-installer.sh && echo "Removed installer" || echo "Failed to remove installer"; }
[[ -n "$NO" ]] && { echo "Cancelled"; exit 1; } || echo "Installer ran successfully"
'

```
---

## Installation

The project includes an interactive installer that supports both guided and non-interactive modes.

### Interactive mode

Run:

```bash
./smb-controller-installer.sh
```

This will:

* Offer you options to:

  * Read the script
  * Install
  * Uninstall
  * Cancel (exit)

* On Install selection:

  * Install the controller script
  * Offer configuration options (example or empty config)
  * Open the config in an editor (can be disabled with -c flag)
  * Optionally install and enable systemd service

* On Uninstall:

  * Stops and disables systemd service (if present)
  * Removes installed binaries and service files
  * Keeps the config file

---

## Non-interactive mode

The installer supports flags for automation:

### Install without prompts

```bash
./smb-controller-installer.sh -i
```

Behavior:

* Installs controller
* Downloads systemd service automatically (no activation or start)
* Uses existing config if present, otherwise installs default
* Skips all prompts
* Does not open editor

---

### Install with local files

```bash
./smb-controller-installer.sh -i -l
```

Use `-l` to use files from the script's directory instead of downloading. Useful for offline installation or custom builds.

---

### Install without systemd

```bash
./smb-controller-installer.sh -i -n
```

Use `-n` to skip systemd service file creation. Useful for systems without systemd or custom setups.

---

### Install with config editing

```bash
./smb-controller-installer.sh -i -c
```

Use `-c` to open the config file in an editor during non-interactive install. In interactive mode, this option disables the automatic config editor prompt.

---

### Install with systemd activation

```bash
./smb-controller-installer.sh -i -a
```

Use `-a` to enable and start the systemd service immediately (requires `-i` without `-n`).

---

### Uninstall mode

```bash
./smb-controller-installer.sh -r
# or
./smb-controller-installer.sh -u
```

Behavior:

* Stops and disables systemd service (if present)
* Removes installed binaries and service files
* Does not prompt for confirmation
* Keeps config file

---

### Uninstall without systemd

```bash
./smb-controller-installer.sh -r -n
```

Use `-n` to skip systemd service removal.

---

### View script before installing

```bash
./smb-controller-installer.sh -i -s
```

Use `-s` to view the script with `less` before proceeding.

---

### Help

```bash
./smb-controller-installer.sh -h
```

Shows full help with all available options and examples.

---

## Configuration

Configuration is defined in:

```

/etc/smb-controller.conf

```

### Structure

- GLOBAL SETTINGS: timing, mount options, base path
- SERVERS: list of SMB servers with credentials
- PATHS: mapping of mount points to servers and remote paths

Example (also in example-smb-controller.conf):

```bash
# =========================
# GLOBAL SETTINGS
# =========================

# Base directory for all mount points (use absolute path)
BASEMNT="/srv/M"

# Timeout in seconds for each port check (server reachability test)
CHECK_TIMEOUT=1

# Number of attempts to mount/unmount on state change
# After this many attempts, the script stops trying and allows manual control
# Example output: "[SMB-media] OFFLINE 3/3" means no more auto-unmount attempts
COUNT_MAX=3

# Wait time in seconds between full server checks
SLEEP=5

# Delay in seconds between each share mount/unmount action
# (prevents load spikes when mounting many shares at once)
SPAWN_DELAY=0.1

# Delay in seconds between processing each server
# (light throttling to reduce CPU usage)
SERVER_DELAY=0.1

# Mount options for CIFS shares
# Examples: uid=root (owner), gid=smbmount (group for access),
# file_mode/dir_mode (permissions), soft (non-blocking)
MOUNT_OPTIONS="uid=root,gid=smbmount,file_mode=0770,dir_mode=0770,soft"

# =========================
# SERVERS
# =========================
# Define SMB servers to monitor
# FORMAT: name:ip:credentials_file
#   name:         friendly identifier (used in PATHS)
#   ip:           IP address or hostname of the server
#   credentials:  path to credentials file (see smb-controller.sh for format)
SERVERS=(
  "media-server:192.168.50.10:/etc/samba/media-smb-credentials"
  "backup-node:192.168.50.11:/etc/samba/backup-smb-credentials"
)

# =========================
# PATHS
# =========================
# Define mount points for each server
# FORMAT: label:mountpoint:remote_path:server_name
#   label:       descriptive name (used in logs)
#   mountpoint:  local directory to mount to (use ${BASEMNT} for global base)
#   remote_path: path on the SMB server to mount
#   server_name: name from SERVERS array to connect to
PATHS=(
  "mediaHome:${BASEMNT}/mediaHome:/home:media-server"
  "mediaData:${BASEMNT}/mediaData:/mnt:media-server"
  "mediaUSB:${BASEMNT}/mediaUSB:/usbs:media-server"

  "backupHome:${BASEMNT}/backupHome:/home:backup-node"
  "backupData:${BASEMNT}/backupData:/mnt:backup-node"
  "backupUSB:${BASEMNT}/backupUSB:/usbs:backup-node"
)
```

---

## System requirements

* Linux system with some sort of backround service
* cifs-utils
* netcat (nc)
* bash 4+

---

## Systemd service

The controller runs as a systemd service for continuous operation (if secected).

Example behavior:

* Starts on boot (if enabled)
* Automatically recovers after restart
* Runs continuously in background

---

## Design goals

This project is designed with the following priorities:

* Avoid blocking filesystem operations
* Prevent file manager freezes (especially KDE Dolphin)
* Keep user control over mounts
* Avoid constant mount/unmount loops
* Be predictable and state-driven rather than event-driven

---

## Safety notes

* Uses lazy unmount (`umount -l`) to prevent blocking on busy mounts
* Designed for trusted LAN environments
* Not intended as a security boundary mechanism
