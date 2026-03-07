#!/bin/bash
# ========================================
# Seagate Auto-Mount Script (FIXED)
# Arch Linux + Steam-safe NTFS
# ========================================

function msg() {
    echo -e "\e[1;34m$1\e[0m"
}
function success() {
    echo -e "\e[1;32m$1\e[0m"
}
function error() {
    echo -e "\e[1;31m$1\e[0m"
}

msg "Searching for Seagate Portable Drive..."

DEVICE=$(lsblk -ln -o NAME,LABEL | grep "Seagate" | awk '{print $1}')

if [ -z "$DEVICE" ]; then
    error "Seagate Portable Drive not found!"
    read -p "Press Enter to exit..."
    exit 1
fi

DEVICE="/dev/$DEVICE"
MOUNT_POINT="/run/media/play/Seagate"

msg "Found device: $DEVICE"

if [ ! -d "$MOUNT_POINT" ]; then
    msg "Creating mount point at $MOUNT_POINT..."
    sudo mkdir -p "$MOUNT_POINT"
fi

if mount | grep -q "$MOUNT_POINT"; then
    msg "Drive already mounted, unmounting first..."
    sudo umount "$MOUNT_POINT" || exit 1
fi

msg "Mounting $DEVICE to $MOUNT_POINT (Steam-safe)..."
sudo mount -t ntfs3 \
-o force,rw,uid=1000,gid=1000,umask=022 \
"$DEVICE" "$MOUNT_POINT"

if mount | grep -q "$MOUNT_POINT"; then
    success "Drive mounted successfully!"

    # Ensure Steam ownership (NTFS ignores chmod otherwise)
    sudo chown -R play:play "$MOUNT_POINT"
else
    error "Failed to mount the drive."
    msg "Check dmesg: sudo dmesg | tail -n 20"
fi

read -p "Press Enter to exit..."
