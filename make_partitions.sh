#!/bin/bash

# Default source and destination devices
SOURCE="/dev/mmcblk0"
DESTINATION="/dev/nvme0n1"

# Function to show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clone partition structure from one disk to another and replicate file systems."
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
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Confirm the operation with the user
echo "Source disk: $SOURCE"
echo "Destination disk: $DESTINATION"
read -p "Are you sure you want to clone the partition structure and file systems? This will overwrite $DESTINATION. (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Backup the GPT partition table from the source disk
echo "Backing up partition table from $SOURCE..."
sgdisk --backup=table.bak "$SOURCE" || { echo "Failed to backup partition table from $SOURCE."; exit 1; }

# Restore the partition table to the destination disk
echo "Restoring partition table to $DESTINATION..."
sgdisk --load-backup=table.bak "$DESTINATION" || { echo "Failed to restore partition table to $DESTINATION."; exit 1; }

# Modify PARTUUIDs on destination disk
echo "Randomizing GUIDs for $DESTINATION..."
sgdisk --randomize-guids "$DESTINATION" || { echo "Failed to randomize GUIDs on $DESTINATION."; exit 1; }

# Inform the OS about the partition table changes
echo "Reloading partition table on $DESTINATION..."
partprobe "$DESTINATION" || { echo "Failed to reload partition table on $DESTINATION."; exit 1; }

# Replicate file systems from source to destination
echo "Replicating file systems..."
# for PART in $(ls "${DESTINATION}"* | grep -E "${DESTINATION}p?[0-9]+$"); do
for PART in $(lsblk -ln -o NAME -p "$DESTINATION" | grep -E "${DESTINATION}p?[0-9]+$"); do
    # Get the corresponding source partition
    PART_NUM=$(echo "$PART" | grep -oE '[0-9]+$')

    # Handle partition naming difference for source device
    if [[ "$SOURCE" == *"mmcblk"* || "$SOURCE" == *"nvme"* ]]; then
        SOURCE_PART="${SOURCE}p${PART_NUM}"
    else
        SOURCE_PART="${SOURCE}${PART_NUM}"
    fi
    echo "Part: $SOURCE_PART"
    # Check if the source partition has a file system
    SRC_FSTYPE=$(blkid -o value -s TYPE "$SOURCE_PART")
    echo "Processing $PART (source: $SOURCE_PART, type: $SRC_FSTYPE)..."
    echo "Source partition: $SOURCE_PART, Detected filesystem: ${SRC_FSTYPE:-None}"

    if [[ -n "$SRC_FSTYPE" ]]; then
        case "$SRC_FSTYPE" in
            ext[234])
                echo "Creating ext4 filesystem on $PART..."
                mkfs.ext4 -F "$PART" && echo "ext4 filesystem created successfully."
                ;;
            vfat|fat32)
                echo "Creating FAT32 filesystem on $PART..."
                mkfs.vfat -F 32 "$PART" && echo "FAT32 filesystem created successfully."
                ;;
            swap)
                echo "Creating swap on $PART..."
                mkswap "$PART" && echo "Swap filesystem created successfully."
                ;;
            *)
                echo "Unsupported filesystem $SRC_FSTYPE on $SOURCE_PART. Skipping..."
                ;;
        esac
    else
        echo "Source partition $SOURCE_PART has no filesystem. Leaving $PART empty."
    fi
done

# Adjust filesystem UUIDs
echo "Adjusting filesystem UUIDs..."
for PART in $(ls "${DESTINATION}"* | grep -E "${DESTINATION}p?[0-9]+$"); do
    FSTYPE=$(blkid -o value -s TYPE "$PART")
    echo "Processing $PART (type: $FSTYPE)..."
    
    if [[ -n "$FSTYPE" ]]; then
        case "$FSTYPE" in
            ext[234])
                echo "Checking filesystem on $PART..."
                e2fsck -f "$PART" && tune2fs -U random "$PART" && echo "Updated UUID for $PART."
                ;;
            swap)
                mkswap -U "$(uuidgen)" "$PART" && echo "Updated UUID for $PART."
                ;;
            vfat|fat32)
                # Get the source partition label
                SRC_LABEL=$(blkid -o value -s LABEL "$SOURCE_PART")
                echo "Source FAT32 label for $SOURCE_PART: ${SRC_LABEL:-<none>}"

                if [[ -n "$SRC_LABEL" ]]; then
                    # Apply the source label to the destination partition
                    echo "Setting FAT32 label: $SRC_LABEL on $PART..."
                    if ! fatlabel "$PART" "$SRC_LABEL"; then
                        echo "Error: FAT32 label '$SRC_LABEL' failed to set on $PART. Labels can be no longer than 11 characters."
                    else
                        echo "Updated label and UUID for $PART with label: $SRC_LABEL."
                    fi
                else
                    echo "Source FAT32 partition $SOURCE_PART has no label. Skipping label assignment for $PART."
                fi
                ;;
            *)
                echo "Filesystem type $FSTYPE on $PART not supported for UUID adjustment."
                ;;
        esac
    else
        echo "Skipping $PART: No filesystem detected."
    fi
done

# Clean up
rm -f table.bak

echo "Partition cloning, file system replication, and UUID adjustment complete."
