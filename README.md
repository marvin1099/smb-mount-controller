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
- All configured shares for that server are mounted (if it was to fail, it will try up to 3 times by default) 

### Offline detection
- If the server is unreachable, an OFFLINE counter increases
- All shares are unmounted using lazy unmount (if it was to fail, it will try up to 3 times by default)

After either action completes, the system stops acting until state changes again.

---

## Configuration

Configuration is defined in:

```

/etc/smb-controller.conf

````

### Structure

- GLOBAL SETTINGS: timing, mount options, base path
- SERVERS: list of SMB servers with credentials
- PATHS: mapping of mount points to servers and remote paths

Example:

```bash
BASEMNT="/srv/M"

CHECK_TIMEOUT=1
COUNT_MAX=3
SLEEP=5
SPAWN_DELAY=0.4
SERVER_DELAY=0.1

MOUNT_OPTIONS="uid=root,gid=smbmount,file_mode=0770,dir_mode=0770,soft"

SERVERS=(
  "media-server:192.168.50.10:/etc/samba/media-smb-credentials"
  "backup-node:192.168.50.11:/etc/samba/backup-smb-credentials"
)

PATHS=(
  "mediaHome:${BASEMNT}/mediaHome:/home:media-server"
  "mediaData:${BASEMNT}/mediaData:/mnt:media-server"

  "backupHome:${BASEMNT}/backupHome:/home:backup-node"
  "backupData:${BASEMNT}/backupData:/mnt:backup-node"
)
```

---

## Quick start

To get started quickly, you can run the installer directly:

```bash
bash <(curl -fsSL https://codeberg.org/marvin1099/smb-mount-controller/raw/branch/main/installer.sh)
```

This is the fastest way to install, but it is recommended to review the script first if you are unsure what it does.

---

## Alternative (safer manual install)

```bash
curl -fsSL https://codeberg.org/marvin1099/smb-mount-controller/raw/branch/main/installer.sh -o installer.sh
chmod +x installer.sh
./installer.sh
```

---

## Installation

The project includes an interactive installer that supports both guided and non-interactive modes.

### Interactive mode

Run:

```bash
./installer.sh
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
  * Open the config in an editor
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
./installer.sh -i
```

Behavior:

* Installs controller
* Downloads systemd service automatically (no activation or start)
* Uses existing config if present, otherwise installs default
* Skips all prompts
* Does not open editor

---

### Uninstall mode

```bash
./installer.sh -r
# or
./installer.sh -u
```

Behavior:

* Stops and disables systemd service (if present)
* Removes installed binaries and service files
* Does not prompt for confirmation
* Keeps config file 

---

### Note

```bash
./installer.sh -h
```
Just shows -i and -r/-u 

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
