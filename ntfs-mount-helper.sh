#!/bin/bash
# ========================================
# NTFS Mount Helper
# A user-friendly tool for mounting dirty NTFS volumes on Linux
# ========================================
set -euo pipefail
VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ntfs-mount-helper"
CONFIG_FILE="$CONFIG_DIR/config.sh"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
function load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        DEFAULT_MOUNT_BASE="/run/media/$USER"
        DEFAULT_UID="$(id -u)"
        DEFAULT_GID="$(id -g)"
    fi

    MOUNT_BASE="${MOUNT_BASE:-$DEFAULT_MOUNT_BASE}"
    USER_UID="${USER_UID:-$DEFAULT_UID}"
    USER_GID="${USER_GID:-$DEFAULT_GID}"
    MOUNT_OPTIONS="${MOUNT_OPTIONS:-force,rw}"
}
function msg() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
function success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
function warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
function error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
function prompt() { echo -e "${CYAN}[?]${NC} $1" >&2; }
function print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "========================================"
    echo " NTFS Mount Helper v$VERSION"
    echo " No Windows Required"
    echo "========================================"
    echo -e "${NC}"
}
function print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]
Commands:
    list, ls List all NTFS volumes (mounted and unmounted)
    mount [DEVICE] Mount an NTFS volume (auto-detect if no device specified)
    unmount [DEVICE] Safely unmount an NTFS volume
    eject [DEVICE] Unmount and safely eject device
    status Show status of all NTFS volumes
    fix [DEVICE] Attempt to fix NTFS issues (ntfsfix)
    recovery [DEVICE] Enter recovery mode (read-only mount for data copy)
    backup [DEVICE] [IMAGE] Create disk image backup using ntfsclone
    interactive, -i Interactive drive selection menu
    config Open configuration file in editor
    help, -h Show this help message
Options:
    -r, --readonly Mount as read-only
    -f, --force Force mount even if dirty (dangerous)
    -n, --nofix Skip auto-fix attempt before mounting
    -v, --verbose Show detailed output
    --dry-run Show what would be done without doing it
Examples:
    $SCRIPT_NAME list
    $SCRIPT_NAME mount
    $SCRIPT_NAME mount /dev/sdb1
    $SCRIPT_NAME mount -r /dev/sdb1
    $SCRIPT_NAME unmount /dev/sdb1
    $SCRIPT_NAME eject
    $SCRIPT_NAME recovery /dev/sdb1
    $SCRIPT_NAME backup /dev/sdb1 ~/backup.img
EOF
}
function get_ntfs_devices() {
    lsblk -rn -o NAME,FSTYPE,LABEL,UUID,SIZE,MOUNTPOINT | \
    awk '$2 == "ntfs" {
        device="/dev/"$1;
        label=$3 ? $3 : "(no label)";
        uuid=$4;
        size=$5;
        mount=$6;
        printf "%s|%s|%s|%s|%s\n", device, label, uuid, size, mount
    }'
}
function list_devices() {
    local verbose="$1"
    local devices

    if [[ -z "$verbose" ]]; then
        devices=$(get_ntfs_devices)
    else
        echo "Fetching detailed device info..."
        devices=$(get_ntfs_devices)
    fi

    if [[ -z "$devices" ]]; then
        warn "No NTFS volumes found."
        return 1
    fi

    echo ""
    printf "${BOLD}%-12s %-20s %-12s %-10s %-15s${NC}\n" "DEVICE" "LABEL" "UUID" "SIZE" "STATUS"
    echo "----------------------------------------------------------------------"

    while IFS='|' read -r device label uuid size mount; do
        if [[ -n "$mount" ]]; then
            printf "%-12s ${GREEN%-20s} %-12s %-10s ${GREEN}%-15s${NC}\n" \
                "$device" "$label" "${uuid:0:12}" "$size" "Mounted"
        else
            local dirty_flag
            dirty_flag=$(is_volume_dirty "$device")
            if [[ "$dirty_flag" == "dirty" ]]; then
                printf "%-12s ${YELLOW%-20s} %-12s %-10s ${YELLOW}%-15s${NC}\n" \
                    "$device" "$label" "${uuid:0:12}" "$size" "Dirty"
            else
                printf "%-12s %-20s %-12s %-10s %-15s\n" \
                    "$device" "$label" "${uuid:0:12}" "$size" "Unmounted"
            fi
        fi
    done <<< "$devices"
    echo ""
}
function is_volume_dirty() {
    local device="$1"
    local ntfs3_info

    ntfs3_info=$(ntfs3info "$device" 2>/dev/null || echo "dirty=0")

    if echo "$ntfs3_info" | grep -q "volume is dirty" 2>/dev/null; then
        echo "dirty"
    elif echo "$ntfs3_info" | grep -q "Dirty" 2>/dev/null; then
        echo "dirty"
    else
        echo "clean"
    fi
}
function detect_dirty_devices() {
    local dirty_devices=()

    while IFS='|' read -r device label uuid size mount; do
        if [[ -z "$mount" ]]; then
            if [[ "$(is_volume_dirty "$device")" == "dirty" ]]; then
                dirty_devices+=("$device|$label|$size")
            fi
        fi
    done <<< "$(get_ntfs_devices)"

    printf '%s\n' "${dirty_devices[@:+${dirty_devices[@]}]}"
}
function get_mount_point() {
    local device="$1"
    local label
    label=$(lsblk -rn -o LABEL "$device" | head -1)

    if [[ -z "$label" || "$label" == "null" ]]; then
        label=$(lsblk -rn -o UUID "$device" | head -1)
    fi

    echo "$MOUNT_BASE/$label"
}
function try_mount_stage() {
    local device="$1"
    local mount_point="$2"
    local fs_type="$3"
    local options="$4"
    local description="$5"

    if [[ "$verbose" == true ]]; then
        msg "Stage: $description"
        msg "Trying: mount -t $fs_type -o $options $device $mount_point"
    fi

    if sudo mount -t "$fs_type" -o "$options" "$device" "$mount_point" 2>&1; then
        return 0
    fi
    return 1
}
function mount_with_recovery() {
    local device="$1"
    local mount_point="$2"
    local label="$3"
    local uuid="$4"
    local size="$5"
    local dirty="$6"

    local uid_opts="uid=$USER_UID,gid=$USER_GID,umask=0022"

    if [[ "$dirty" == "dirty" ]]; then
        echo ""
        warn "=============================================="
        warn " Volume is marked DIRTY"
        warn " Attempting multi-stage recovery..."
        warn "=============================================="
        echo ""
    fi

    local stage=1
    local mount_success=false

    while [[ $stage -le 6 ]]; do
        case $stage in
            1)
                msg "[Stage 1/6] ntfs3 with force (standard approach)..."
                if try_mount_stage "$device" "$mount_point" "ntfs3" "force,rw,$uid_opts" "ntfs3 force"; then
                    mount_success=true
                fi
                ;;
            2)
                msg "[Stage 2/6] ntfs3 read-only (safest)..."
                if try_mount_stage "$device" "$mount_point" "ntfs3" "ro,$uid_opts" "ntfs3 readonly"; then
                    mount_success=true
                    warn "Mounted READ-ONLY. You can copy data but not modify."
                fi
                ;;
            3)
                msg "[Stage 3/6] ntfs-3g (FUSE driver - more forgiving)..."
                if try_mount_stage "$device" "$mount_point" "ntfs-3g" "force,rw,$uid_opts" "ntfs-3g force"; then
                    mount_success=true
                fi
                ;;
            4)
                msg "[Stage 4/6] ntfs-3g read-only..."
                if try_mount_stage "$device" "$mount_point" "ntfs-3g" "ro,$uid_opts" "ntfs-3g readonly"; then
                    mount_success=true
                    warn "Mounted READ-ONLY. You can copy data but not modify."
                fi
                ;;
            5)
                msg "[Stage 5/6] Running ntfsfix and retrying..."
                if command -v ntfsfix &>/dev/null; then
                    sudo ntfsfix -d "$device" 2>&1 | head -3 || true
                    if try_mount_stage "$device" "$mount_point" "ntfs3" "force,rw,$uid_opts" "ntfs3 after ntfsfix"; then
                        mount_success=true
                    fi
                else
                    warn "ntfsfix not available"
                fi
                ;;
            6)
                msg "[Stage 6/6] Last resort: ntfsfix full repair..."
                if command -v ntfsfix &>/dev/null; then
                    sudo ntfsfix "$device" 2>&1 | head -5 || true
                    if try_mount_stage "$device" "$mount_point" "ntfs3" "force,rw,$uid_opts" "ntfs3 after full ntfsfix"; then
                        mount_success=true
                    fi
                fi
                ;;
        esac

        if [[ "$mount_success" == true ]]; then
            return 0
        fi

        ((stage++))
    done

    return 1
}
function show_recovery_options() {
    local device="$1"
    local mount_point="$2"

    echo ""
    error "=============================================="
    error " All recovery stages failed"
    error "=============================================="
    echo ""
    echo "Your options (in order of recommendation):"
    echo ""
    echo -e "${YELLOW}1.${NC} Use ${BOLD}recovery mode${NC} to copy your data"
    echo " Command: $SCRIPT_NAME recovery $device"
    echo ""
    echo -e "${YELLOW}2.${NC} Clone the drive to a new disk using ntfsclone"
    echo " This can sometimes recover data from corrupted drives"
    echo " Command: sudo ntfsclone --rescue --output /path/to/backup.img $device"
    echo ""
    echo -e "${YELLOW}3.${NC} Boot into Windows and run: ${BOLD}chkdsk /f${NC}"
    echo " This is the most reliable repair method"
    echo ""
    echo -e "${YELLOW}4.${NC} Use TestDisk/PhotoRec for data recovery"
    echo " Install: sudo apt install testdisk"
    echo ""
}
function recovery_mode() {
    local device="${1:-}"

    if [[ -z "$device" ]]; then
        device=$(select_device "recover")
        [[ -z "$device" ]] && exit 0
    fi

    if [[ ! -b "$device" ]]; then
        error "Invalid device: $device"
        exit 1
    fi

    local label uuid size current_mount
    label=$(lsblk -rn -o LABEL "$device" | head -1)
    uuid=$(lsblk -rn -o UUID "$device" | head -1)
    size=$(lsblk -rn -o SIZE "$device" | head -1)
    current_mount=$(lsblk -rn -o MOUNTPOINT "$device" | head -1)

    echo ""
    warn "=============================================="
    warn " NTFS Recovery Mode"
    warn " Read-only data extraction"
    warn "=============================================="
    echo ""
    echo "Device: $device"
    echo "Label: ${label:-N/A}"
    echo "Size: $size"
    echo ""

    if [[ -n "$current_mount" ]]; then
        warn "Device already mounted at: $current_mount"
        prompt "Use this mount point? [Y/n] "
        read -r answer
        if [[ "$answer" =~ ^[Nn]$ ]]; then
            exit 0
        fi
        local mount_point="$current_mount"
    else
        local mount_point
        mount_point=$(get_mount_point "$device")

        load_config
        local uid_opts="uid=$USER_UID,gid=$USER_GID,umask=0022"

        msg "Attempting read-only mount..."

        if try_mount_stage "$device" "$mount_point" "ntfs3" "ro,$uid_opts" "ntfs3 readonly"; then
            success "Mounted read-only!"
        elif try_mount_stage "$device" "$mount_point" "ntfs-3g" "ro,$uid_opts" "ntfs-3g readonly"; then
            success "Mounted read-only!"
        else
            error "Could not mount read-only"
            prompt "Try force mount anyway? [y/N] "
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                sudo mkdir -p "$mount_point"
                if sudo mount -t ntfs3 -o "force,ro,$uid_opts" "$device" "$mount_point" 2>&1; then
                    success "Mounted with force-readonly"
                else
                    error "All attempts failed"
                    show_recovery_options "$device" "$mount_point"
                    return 1
                fi
            else
                return 1
            fi
        fi
    fi

    echo ""
    success "=============================================="
    success " RECOVERY MOUNT SUCCESSFUL"
    success "=============================================="
    echo ""
    echo -e "${GREEN}Mount point: $mount_point${NC}"
    echo ""
    echo "You can now copy your data:"
    echo " cp -r $mount_point ~/backup/"
    echo ""
    warn "When done, unmount with: sudo umount $mount_point"
    echo ""
}
function backup_ntfs() {
    local device="${1:-}"
    local image="${2:-}"
    local dry_run=false

    shift 2 || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$device" ]]; then
        device=$(select_device "backup")
        [[ -z "$device" ]] && exit 0
    fi

    if [[ -z "$image" ]]; then
        prompt "Enter backup image path (e.g., ~/backup.img): "
        read -r image
        if [[ -z "$image" ]]; then
            error "No image path provided."
            exit 1
        fi
    fi

    if ! command -v ntfsclone &>/dev/null; then
        error "ntfsclone not found. Install ntfs-3g package."
        exit 1
    fi

    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would execute: sudo ntfsclone --rescue --output $image $device"
        exit 0
    fi

    msg "Creating NTFS clone image with rescue mode..."
    sudo ntfsclone --rescue --output "$image" "$device"

    if [[ $? -eq 0 ]]; then
        success "Backup created at $image"
    else
        error "Backup failed. Check for errors above."
    fi
}
function mount_ntfs() {
    local device="${1:-}"
    local readonly_mount=""
    local force_mount=""
    local auto_fix=true
    local verbose=false
    local dry_run=false

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--readonly) readonly_mount="ro"; force_mount="ro"; shift ;;
            -f|--force) force_mount="force"; shift ;;
            -n|--nofix) auto_fix=false; shift ;;
            -v|--verbose) verbose=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    load_config

    local devices

    if [[ -z "$device" ]]; then
        devices=$(get_ntfs_devices)

        if [[ -z "$devices" ]]; then
            error "No NTFS volumes found."
            exit 1
        fi

        local count
        count=$(echo "$devices" | wc -l)

        if [[ $count -eq 1 ]]; then
            device=$(echo "$devices" | head -1 | cut -d'|' -f1)
        else
            device=$(select_device "mount")
            [[ -z "$device" ]] && exit 0
        fi
    fi

    if [[ ! -b "$device" ]]; then
        error "Invalid device: $device"
        exit 1
    fi

    local label uuid size current_mount
    label=$(lsblk -rn -o LABEL "$device" | head -1)
    uuid=$(lsblk -rn -o UUID "$device" | head -1)
    size=$(lsblk -rn -o SIZE "$device" | head -1)
    current_mount=$(lsblk -rn -o MOUNTPOINT "$device" | head -1)

    if [[ -n "$current_mount" ]]; then
        warn "Device is already mounted at: $current_mount"
        printf "%s" "[?] Unmount first? [Y/n] "
        read -r answer
        echo ""
        if [[ "$answer" =~ ^[Yy]*$ ]] || [[ -z "$answer" ]]; then
            unmount_ntfs "$device" || exit 1
        else
            exit 0
        fi
    fi

    local mount_point
    mount_point=$(get_mount_point "$device")

    local dirty
    dirty=$(is_volume_dirty "$device")

    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would attempt multi-stage recovery on: $device"
        echo "Mount point: $mount_point"
        exit 0
    fi

    msg "Creating mount point: $mount_point"
    sudo mkdir -p "$mount_point"

    if [[ -n "$readonly_mount" ]]; then
        msg "Attempting read-only mount..."
        local uid_opts="uid=$USER_UID,gid=$USER_GID,umask=0022"
        local mount_opts="${force_mount:-force},ro,$uid_opts"

        if try_mount_stage "$device" "$mount_point" "ntfs3" "$mount_opts" "ntfs3 readonly force"; then
            success "Mounted read-only!"
        elif try_mount_stage "$device" "$mount_point" "ntfs-3g" "$mount_opts" "ntfs-3g readonly force"; then
            success "Mounted read-only!"
        else
            error "Could not mount read-only"
            return 1
        fi
    elif mount_with_recovery "$device" "$mount_point" "$label" "$uuid" "$size" "$dirty"; then
        success "Mounted successfully!"
    else
        error "Failed to mount after all recovery attempts"
        show_recovery_options "$device" "$mount_point"
        return 1
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} Device: $device${NC}"
    echo -e "${GREEN} Label: ${label:-N/A}${NC}"
    echo -e "${GREEN} UUID: ${uuid:-N/A}${NC}"
    echo -e "${GREEN} Size: $size${NC}"
    echo -e "${GREEN} Mount: $mount_point${NC}"
    echo -e "${GREEN}========================================${NC}"

    if [[ -n "$label" && "$label" != "null" ]]; then
        sudo chown -R "$USER_UID:$USER_GID" "$mount_point" 2>/dev/null || true
    fi

    return 0
}
function unmount_ntfs() {
    local device="${1:-}"
    local force=false
    local dry_run=false

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$device" ]]; then
        device=$(select_device "unmount")
        [[ -z "$device" ]] && exit 0
    fi

    local current_mount
    current_mount=$(lsblk -rn -o MOUNTPOINT "$device" | head -1)

    if [[ -z "$current_mount" ]]; then
        warn "Device $device is not mounted."
        return 1
    fi

    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would execute: sudo umount $current_mount"
        exit 0
    fi

    msg "Unmounting $device from $current_mount..."

    if [[ "$force" == true ]]; then
        sudo umount -f "$current_mount" || sudo umount -l "$current_mount"
    else
        sudo umount "$current_mount"
    fi

    if [[ $? -eq 0 ]]; then
        success "Unmounted successfully."
        sudo rmdir "$current_mount" 2>/dev/null || true
    else
        error "Failed to unmount. Device may be in use."
        prompt "Force unmount? [y/N] "
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sudo umount -f "$current_mount" || sudo umount -l "$current_mount"
            success "Force unmounted."
            sudo rmdir "$current_mount" 2>/dev/null || true
        fi
    fi
}
function eject_device() {
    local device="${1:-}"

    if [[ -z "$device" ]]; then
        device=$(select_device "eject")
        [[ -z "$device" ]] && exit 0
    fi

    local current_mount
    current_mount=$(lsblk -rn -o MOUNTPOINT "$device" | head -1)

    if [[ -n "$current_mount" ]]; then
        msg "Unmounting before eject..."
        sudo umount "$current_mount" || sudo umount -l "$current_mount"
    fi

    local dev_name
    dev_name=$(basename "$device")

    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would execute: sudo eject /dev/$dev_name"
        exit 0
    fi

    msg "Ejecting $device..."
    if command -v eject &>/dev/null; then
        sudo eject "/dev/$dev_name"
        success "Device ejected. It is now safe to remove."
    else
        error "eject command not found. Install eject package."
        warn "You can safely remove the device manually now."
    fi
}
function fix_ntfs() {
    local device="${1:-}"
    local backup_mode=false
    local dry_run=false

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--backup) backup_mode=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$device" ]]; then
        device=$(select_device "fix")
        [[ -z "$device" ]] && exit 0
    fi

    if [[ ! -b "$device" ]]; then
        error "Invalid device: $device"
        exit 1
    fi

    if ! command -v ntfsfix &>/dev/null; then
        error "ntfsfix not found. Install ntfs-3g package."
        exit 1
    fi

    local label uuid
    label=$(lsblk -rn -o LABEL "$device" | head -1)
    uuid=$(lsblk -rn -o UUID "$device" | head -1)

    echo ""
    warn "Fixing NTFS volume: $device ($label)"
    echo "UUID: $uuid"
    echo ""

    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would execute:"
        if [[ "$backup_mode" == true ]]; then
            echo " sudo ntfsfix -b $device"
            echo " sudo ntfsfix -n $device"
        else
            echo " sudo ntfsfix $device"
        fi
        exit 0
    fi

    msg "Running ntfsfix (clear dirty flag)..."
    sudo ntfsfix "$device"

    if [[ "$backup_mode" == true ]]; then
        msg "Running ntfsfix in backup mode..."
        sudo ntfsfix -b "$device"
        sudo ntfsfix -n "$device"
    fi

    success "Fix complete."
    msg "Try mounting the device now."
}
function select_device() {
    local action="$1"
    local devices
    devices=$(get_ntfs_devices)

    if [[ -z "$devices" ]]; then
        error "No NTFS volumes found."
        return 1
    fi

    local count
    count=$(echo "$devices" | wc -l)

    if [[ $count -eq 1 ]]; then
        echo "$(echo "$devices" | cut -d'|' -f1)"
        return 0
    fi

    echo "" >&2
    printf "%s" "[?] Select a device to $action: " >&2
    echo "" >&2

    local index=1
    local options=()
    while IFS='|' read -r device label uuid size mount; do
        local status
        if [[ -n "$mount" ]]; then
            status="${GREEN}Mounted${NC}"
        elif [[ "$(is_volume_dirty "$device")" == "dirty" ]]; then
            status="${YELLOW}Dirty${NC}"
        else
            status="Unmounted"
        fi

        printf " ${BOLD}%2d)${NC} %-12s %-20s %-10s %s\n" \
            "$index" "$device" "$label" "$size" "$status" >&2

        options+=("$device")
        ((index++))
    done <<< "$devices"

    echo "" >&2
    printf "%s" "[?] Enter number [1-$count] or 'q' to cancel: " >&2
    read -r choice
    echo "" >&2

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        return 1
    fi

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $count ]]; then
        error "Invalid selection."
        return 1
    fi

    echo "${options[$((choice-1))]}"
    return 0
}
function show_status() {
    local devices
    devices=$(get_ntfs_devices)

    if [[ -z "$devices" ]]; then
        warn "No NTFS volumes found."
        return 1
    fi

    echo ""
    printf "${BOLD}%-12s %-20s %-12s %-10s %-15s %s${NC}\n" \
        "DEVICE" "LABEL" "UUID" "SIZE" "STATUS" "MOUNT POINT"
    echo "--------------------------------------------------------------------------------"

    while IFS='|' read -r device label uuid size mount; do
        if [[ -n "$mount" ]]; then
            printf "%-12s ${GREEN}%-20s${NC} %-12s %-10s ${GREEN}%-15s${NC} %s\n" \
                "$device" "$label" "${uuid:0:12}" "$size" "Mounted" "$mount"
        else
            local dirty
            dirty=$(is_volume_dirty "$device")
            if [[ "$dirty" == "dirty" ]]; then
                printf "%-12s ${YELLOW}%-20s${NC} %-12s %-10s ${YELLOW}%-15s${NC} -\n" \
                    "$device" "$label" "${uuid:0:12}" "$size" "Dirty"
            else
                printf "%-12s %-20s %-12s %-10s %-15s -\n" \
                    "$device" "$label" "${uuid:0:12}" "$size" "Unmounted"
            fi
        fi
    done <<< "$devices"
    echo ""
}
function interactive_menu() {
    while true; do
        print_header
        echo -e "${CYAN}=== Quick Fix ===${NC}"
        echo -e " ${BOLD}1${NC}) Mount NTFS volume"
        echo -e " ${BOLD}2${NC}) Unmount NTFS volume"
        echo -e " ${BOLD}3${NC}) List all volumes"
        echo -e " ${BOLD}4${NC}) Show status"
        echo -e " ${BOLD}5${NC}) Open config"
        echo ""
        echo -e "${CYAN}=== Advanced ===${NC}"
        echo -e " ${BOLD}6${NC}) Fix NTFS volume"
        echo -e " ${BOLD}7${NC}) Recovery mode"
        echo -e " ${BOLD}8${NC}) Backup to image"
        echo -e " ${BOLD}9${NC}) Eject device"
        echo ""
        echo -e " ${BOLD}q${NC}) Quit"
        echo ""

        printf "%s" "[?] Select an option: "
        read -r choice
        echo ""

        case "$choice" in
            1) mount_ntfs "" ;;
            2)
                device=$(select_device "unmount")
                [[ -n "$device" ]] && unmount_ntfs "$device"
                ;;
            3) list_devices "verbose" ;;
            4) show_status ;;
            5)
                load_config
                mkdir -p "$CONFIG_DIR"
                if [[ ! -f "$CONFIG_FILE" ]]; then
                    cat > "$CONFIG_FILE" << 'EOFCONFIG'
# NTFS Mount Helper Configuration
# Base directory for mount points
MOUNT_BASE="/run/media/$USER"
# User and group ID (default: current user)
USER_UID="1000"
USER_GID="1000"
# Default mount options
MOUNT_OPTIONS="force,rw"
# Auto-fix dirty volumes before mounting (true/false)
AUTO_FIX=true
# Show confirmation prompts (true/false)
CONFIRM_PROMPTS=true
EOFCONFIG
                fi
                ${EDITOR:-nano} "$CONFIG_FILE"
                ;;
            6)
                device=$(select_device "fix")
                [[ -n "$device" ]] && fix_ntfs "$device"
                ;;
            7)
                device=$(select_device "recover")
                [[ -n "$device" ]] && recovery_mode "$device"
                ;;
            8)
                device=$(select_device "backup")
                if [[ -n "$device" ]]; then
                    prompt "Enter backup image path (e.g., ~/backup.img): "
                    read -r image
                    backup_ntfs "$device" "$image"
                fi
                ;;
            9)
                device=$(select_device "eject")
                [[ -n "$device" ]] && eject_device "$device"
                ;;
            q|Q) exit 0 ;;
            *) error "Invalid option." ;;
        esac

        if [[ "$choice" =~ ^[1-9]$ ]]; then
            echo ""
            prompt "Press Enter to continue..."
            read -r
        fi
    done
}
function init_config() {
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOFCONFIG'
# NTFS Mount Helper Configuration
# This file is sourced by the main script
# Base directory for mount points
MOUNT_BASE="/run/media/$USER"
# User and group ID (default: current user)
USER_UID="1000"
USER_GID="1000"
# Default mount options
MOUNT_OPTIONS="force,rw"
# Auto-fix dirty volumes before mounting (true/false)
AUTO_FIX=true
# Show confirmation prompts (true/false)
CONFIRM_PROMPTS=true
EOFCONFIG
        success "Configuration file created at: $CONFIG_FILE"
    fi
}
COMMAND="${1:-}"
DRY_RUN=false
case "$COMMAND" in
    list|ls)
        list_devices "${2:-}"
        ;;
    mount)
        mount_ntfs "${2:-}" "${@:3}"
        ;;
    unmount|umount)
        unmount_ntfs "${2:-}" "${@:3}"
        ;;
    eject)
        eject_device "${2:-}"
        ;;
    fix)
        fix_ntfs "${2:-}" "${@:3}"
        ;;
    recovery)
        recovery_mode "${2:-}"
        ;;
    backup)
        backup_ntfs "${2:-}" "${3:-}" "${@:4}"
        ;;
    status)
        show_status
        ;;
    interactive|-i)
        interactive_menu
        ;;
    config)
        init_config
        load_config
        ${EDITOR:-nano} "$CONFIG_FILE"
        ;;
    help|-h|--help)
        print_usage
        ;;
    "")
        interactive_menu
        ;;
    *)
        error "Unknown command: $COMMAND"
        echo ""
        print_usage
        exit 1
        ;;
esac
