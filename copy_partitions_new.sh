#!/bin/bash

set -e  # Exit immediately on error

# Safety check - require root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

SOURCE="/dev/mmcblk0"
DESTINATION="/dev/nvme0n1"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Copy contents of partitions from source disk to destination disk."
    echo
    echo "Options:"
    echo "  -s, --source      Source disk (default: /dev/mmcblk0)"
    echo "  -d, --destination Destination disk (default: /dev/nvme0n1)"
    echo "  -h, --help        Show this help message and exit"
    echo
    exit 0
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -s|--source) SOURCE="$2"; shift 2 ;;
        -d|--destination) DESTINATION="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
done

# Confirm the operation
echo "Source disk: $SOURCE"
echo "Destination disk: $DESTINATION"
read -p "Are you sure you want to copy contents from $SOURCE to $DESTINATION? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Ensure devices exist
if [[ ! -b "$SOURCE" || ! -b "$DESTINATION" ]]; then
    echo "Error: Source or destination disk does not exist."
    exit 1
fi

# Enumerate partitions
SOURCE_PARTS=$(lsblk -ln -o NAME,MOUNTPOINT -p "$SOURCE" | grep -E "${SOURCE}p?[0-9]+" | awk '{print $1}')
DEST_PARTS=$(lsblk -ln -o NAME -p "$DESTINATION" | grep -E "${DESTINATION}p?[0-9]+$")

if [[ -z "$SOURCE_PARTS" || -z "$DEST_PARTS" ]]; then
    echo "Error: Failed to enumerate partitions on $SOURCE or $DESTINATION."
    exit 1
fi

# Copy contents
for SOURCE_PART in $SOURCE_PARTS; do
    PART_NUM=$(echo "$SOURCE_PART" | grep -oE '[0-9]+$')

    # Match corresponding destination partition
    if [[ "$SOURCE" == *"mmcblk"* || "$SOURCE" == *"nvme"* ]]; then
        DEST_PART="${DESTINATION}p${PART_NUM}"
    else
        DEST_PART="${DESTINATION}${PART_NUM}"
    fi

    # Ensure destination partition exists
    if [[ ! -b "$DEST_PART" ]]; then
        echo "Warning: Destination partition $DEST_PART does not exist. Skipping..."
        continue
    fi

    # Identify filesystems
    SRC_FSTYPE=$(blkid -o value -s TYPE "$SOURCE_PART")
    DEST_FSTYPE=$(blkid -o value -s TYPE "$DEST_PART" || echo "")

    echo "Checking filesystem compatibility from $SOURCE_PART ($SRC_FSTYPE) to $DEST_PART ($DEST_FSTYPE)..."

    # If source has no filesystem, perform raw copy
    if [[ -z "$SRC_FSTYPE" ]]; then
        echo "Source partition $SOURCE_PART has no filesystem. Performing raw copy using dd..."
        dd if="$SOURCE_PART" of="$DEST_PART" bs=4M status=progress conv=fsync || {
            echo "Error: Failed raw copy from $SOURCE_PART to $DEST_PART."
            continue
        }
        echo "Raw copy from $SOURCE_PART to $DEST_PART completed."
        continue
    fi

    # Handle mismatched filesystems
    if [[ "$SRC_FSTYPE" != "$DEST_FSTYPE" ]]; then
        echo "Filesystem mismatch detected!"
        echo "Source: $SOURCE_PART ($SRC_FSTYPE)"
        echo "Destination: $DEST_PART ($DEST_FSTYPE)"
        read -p "Do you want to format $DEST_PART to $SRC_FSTYPE? (yes/no): " FORMAT_CONFIRM
        if [[ "$FORMAT_CONFIRM" != "yes" ]]; then
            echo "Skipping $SOURCE_PART due to mismatched filesystems."
            continue
        fi

        echo "Formatting $DEST_PART as $SRC_FSTYPE..."
        case "$SRC_FSTYPE" in
            ext4) mkfs.ext4 -F "$DEST_PART" ;;
            xfs) mkfs.xfs -f "$DEST_PART" ;;
            vfat) mkfs.vfat "$DEST_PART" ;;
            exfat) mkfs.exfat "$DEST_PART" ;;
            *) echo "Unsupported filesystem type: $SRC_FSTYPE"; exit 1 ;;
        esac
    fi

    # Mount the source and destination partitions
    SRC_MOUNT="/mnt/source_$PART_NUM"
    DEST_MOUNT="/mnt/destination_$PART_NUM"
    mkdir -p "$SRC_MOUNT" "$DEST_MOUNT"
    mount -o ro "$SOURCE_PART" "$SRC_MOUNT" || { echo "Error: Failed to mount $SOURCE_PART"; continue; }
    mount "$DEST_PART" "$DEST_MOUNT" || { echo "Error: Failed to mount $DEST_PART"; umount "$SRC_MOUNT"; continue; }

    # Perform rsync copy
    echo "Copying from $SOURCE_PART to $DEST_PART..."
    rsync -aAXv --progress "$SRC_MOUNT/" "$DEST_MOUNT/" || {
        echo "Error: Failed to sync $SOURCE_PART to $DEST_PART."
    }

    # Unmount and clean up
    umount "$DEST_MOUNT" "$SRC_MOUNT"
    rmdir "$DEST_MOUNT" "$SRC_MOUNT"

done

echo "Partition content copy complete."
