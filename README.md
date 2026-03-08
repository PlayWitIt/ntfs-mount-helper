# NTFS Mount Helper

<p align="center">
  <strong>A user-friendly tool for mounting dirty NTFS volumes on Linux</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#requirements">Requirements</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Overview

NTFS Mount Helper solves a common problem faced by Linux users who have external NTFS drives (from Windows): the dreaded **"Volume is dirty"** error that prevents mounting.

This tool provides a simple, safe, and user-friendly way to:

- Detect and mount any NTFS drive automatically
- Handle dirty volumes with configurable safety options
- Safely unmount and eject devices
- Fix common NTFS issues without booting Windows

---

## Features

- **Auto-detection**: Automatically finds all NTFS volumes on your system
- **Dirty volume handling**: Offers safe options for mounting dirty volumes
- **Interactive menu**: Easy-to-use TUI for drive selection
- **Multiple mount options**: Read-only, read-write, force mount
- **Safe removal**: Proper unmount and eject functionality
- **NTFS repair**: Built-in ntfsfix integration
- **Configuration file**: Persistent settings across sessions
- **Color-coded output**: Clear visual feedback
- **Dry-run mode**: Preview actions before executing
- **Works with any drive**: Not limited to specific brands

---

## Requirements

- Linux system with `ntfs3` kernel module (most modern kernels)
- `ntfs-3g` package (for ntfsfix)
- `eject` package (optional, for safe ejection)
- `sudo` privileges
- Bash 4.0+

### Install dependencies

**Debian/Ubuntu:**
```bash
sudo apt install ntfs-3g eject
```

**Arch Linux:**
```bash
sudo pacman -S ntfs-3g eject
```

**Fedora:**
```bash
sudo dnf install ntfs-3g eject
```

---

## Installation

### Quick Install

1. Download the script:
```bash
curl -O https://raw.githubusercontent.com/PlayWitIt/ntfs-mount-helper/main/ntfs-mount-helper.sh
```

2. Make it executable:
```bash
chmod +x ntfs-mount-helper.sh
```

3. Run it:
```bash
./ntfs-mount-helper.sh
```

### System-wide Installation

For system-wide access (available to all users):

```bash
sudo cp ntfs-mount-helper.sh /usr/local/bin/ntfs-mount-helper
sudo chmod +x /usr/local/bin/ntfs-mount-helper
```

Now you can run it from anywhere:
```bash
ntfs-mount-helper
```

---

## Usage

### Interactive Mode (Recommended)

Simply run the script without arguments:
```bash
./ntfs-mount-helper.sh
```

This opens an interactive menu where you can:
- Mount volumes
- Unmount volumes
- Eject devices
- Fix NTFS issues
- View all NTFS volumes

### Command-Line Mode

#### List all NTFS volumes
```bash
./ntfs-mount-helper.sh list
```

Output:
```
DEVICE        LABEL                UUID         SIZE       STATUS
/dev/sdb1     Seagate Backup       A1B2C3D4     1.0T       Unmounted
/dev/sdc1     Windows              E5F6G7H8     500G       Mounted
/dev/sdc2     Data                 I9J0K1L2     1.0T       Dirty
```

#### Mount a volume (auto-detect)
```bash
./ntfs-mount-helper.sh mount
```

#### Mount a specific device
```bash
./ntfs-mount-helper.sh mount /dev/sdb1
```

#### Mount as read-only
```bash
./ntfs-mount-helper.sh mount -r /dev/sdb1
```

#### Mount with verbose output
```bash
./ntfs-mount-helper.sh mount -v /dev/sdb1
```

#### Preview mount without executing
```bash
./ntfs-mount-helper.sh mount --dry-run /dev/sdb1
```

#### Unmount a volume
```bash
./ntfs-mount-helper.sh unmount /dev/sdb1
```

#### Force unmount (if busy)
```bash
./ntfs-mount-helper.sh unmount -f /dev/sdb1
```

#### Eject device safely
```bash
./ntfs-mount-helper.sh eject /dev/sdb1
```

#### Fix NTFS issues
```bash
./ntfs-mount-helper.sh fix /dev/sdb1
```

#### Fix with backup mode
```bash
./ntfs-mount-helper.sh fix -b /dev/sdb1
```

#### Show status of all NTFS volumes
```bash
./ntfs-mount-helper.sh status
```

---

## Configuration

### Creating Config File

Run the config command to create a configuration file:
```bash
./ntfs-mount-helper.sh config
```

This creates `~/.config/ntfs-mount-helper/config.sh` with default settings.

### Configuration Options

```bash
# Base directory for mount points
MOUNT_BASE="/run/media/$USER"

# User and group ID (match your user)
UID="1000"
GID="1000"

# Default mount options
MOUNT_OPTIONS="force,rw"

# Auto-fix dirty volumes before mounting
AUTO_FIX=true

# Show confirmation prompts
CONFIRM_PROMPTS=true
```

---

## Command-Line Options

| Option | Description |
|--------|-------------|
| `-r, --readonly` | Mount as read-only |
| `-f, --force` | Force mount even if dirty |
| `-n, --nofix` | Skip auto-fix attempt |
| `-v, --verbose` | Show detailed output |
| `--dry-run` | Preview without executing |
| `-b, --backup` | Use backup mode for ntfsfix |

---

## How It Works

### Mount Process

1. **Detection**: Scans system for all NTFS volumes
2. **Selection**: If multiple drives, lets user choose (or auto-selects if only one)
3. **Check**: Checks if volume is marked dirty
4. **Auto-fix** (optional): Offers to run ntfsfix to clear dirty flag
5. **Mount**: Mounts with appropriate options
6. **Permissions**: Sets correct ownership

### Safety Features

- **Dirty volume warning**: Clearly warns about risks
- **Confirmation prompts**: Prevents accidental data loss
- **Auto-fix option**: Tries ntfsfix before force mount
- **Read-only mode**: Safe option for data recovery
- **Dry-run mode**: Preview before execution

---

## Troubleshooting

### "No NTFS volumes found"

- Ensure the drive is connected and powered
- Check if the device is detected: `lsblk`
- Verify ntfs3 module is loaded: `lsmod | grep ntfs`

### "Mount failed"

- Check kernel messages: `sudo dmesg | tail -20`
- The volume may need Windows chkdsk
- Try read-only mode: `mount -r`

### "Permission denied"

- Ensure you have sudo privileges
- Check configuration UID/GID matches your user

### Drive still shows as dirty after fix

- Some corruption requires Windows chkdsk
- Try backup mode: `fix -b /dev/sdX`
- Boot into Windows and run: `chkdsk /f`

### ntfsfix not found

Install ntfs-3g package:
```bash
# Debian/Ubuntu
sudo apt install ntfs-3g

# Arch
sudo pacman -S ntfs-3g
```

---

## Warnings

> **⚠️ Important Safety Notes**
>
> - **Dirty volumes**: A dirty flag indicates potential filesystem corruption. While force mounting often works, there's a small risk of data loss.
> 
> - **Always unmount properly**: Never unplug the drive while data is being written. Use the unmount/eject function.
> 
> - **Backup important data**: If a drive shows persistent issues, back up your data as soon as possible.
> 
> - **Windows Fast Startup**: If using dual-boot, disable Windows Fast Startup to prevent dirty volumes:
>   - Windows Settings → System → Power & sleep → Additional power settings
>   - Choose "Choose what the power buttons do"
>   - Uncheck "Turn on fast startup"

---

## Similar Tools

- **ntfs-3g**: Traditional FUSE driver (older, more mature)
- **ntfs3**: Newer kernel-native driver (faster, used by this script)
- **ntfsfix**: Part of ntfs-3g, clears dirty flag
- **chkdsk**: Windows tool (most reliable for NTFS repair)

---

## License

MIT License - Copyright (c) 2026 PlayWit Creations. Free to use, modify, and distribute.

---

## Contributing

Contributions welcome! Please open an issue or pull request on GitHub.
