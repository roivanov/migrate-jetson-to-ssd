#!/bin/bash

# Default destination device
DESTINATION="/dev/nvme0n1"

# Function to show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Script to update system configurations for SSD boot after cloning."
    echo
    echo "Options:"
    echo "  -d, --destination Destination disk (default: /dev/nvme0n1)"
    echo "  -h, --help        Show this help message and exit"
    echo
    exit 0
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
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

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Determine the UUID of the 10th partition on the destination
echo "Determining the UUID of partition 10 on $DESTINATION..."
PART10="${DESTINATION}p10"
if [[ ! -b "$PART10" ]]; then
    echo "Error: Partition 10 does not exist on $DESTINATION."
    exit 1
fi
PART10_UUID=$(blkid -o value -s UUID "$PART10")
if [[ -z "$PART10_UUID" ]]; then
    echo "Error: Partition 10 on $DESTINATION does not have a UUID."
    exit 1
fi
echo "Partition 10 UUID: $PART10_UUID"

# Step 1: Modify /boot/extlinux/extlinux.conf
EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
echo "Modifying $EXTLINUX_CONF to set root to the first partition of $DESTINATION..."
if [[ ! -f "$EXTLINUX_CONF" ]]; then
    echo "Error: $EXTLINUX_CONF not found."
    exit 1
fi

# Backup extlinux.conf
cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.bak" || {
    echo "Error: Failed to create backup of $EXTLINUX_CONF."
    exit 1
}
echo "Backup of extlinux.conf created at ${EXTLINUX_CONF}.bak."

# Update the root partition in extlinux.conf
sed -i "s|root=[^ ]*|root=${DESTINATION}p1|" "$EXTLINUX_CONF" || {
    echo "Error: Failed to update $EXTLINUX_CONF."
    exit 1
}
echo "$EXTLINUX_CONF updated successfully."

# Step 2: Modify /etc/fstab
FSTAB="/etc/fstab"
echo "Modifying $FSTAB to match the UUID of partition 10 on $DESTINATION..."
if [[ ! -f "$FSTAB" ]]; then
    echo "Error: $FSTAB not found."
    exit 1
fi

# Backup fstab
cp "$FSTAB" "${FSTAB}.bak" || {
    echo "Error: Failed to create backup of $FSTAB."
    exit 1
}
echo "Backup of fstab created at ${FSTAB}.bak."

# Update the fstab entry for partition 10
sed -i "/\/boot\/efi / s|UUID=[^ ]*|UUID=${PART10_UUID}|" "$FSTAB" || {
    echo "Error: Failed to update $FSTAB."
    exit 1
}
echo "$FSTAB updated successfully."

echo "System configurations updated for SSD boot."
echo "You may have to change the boot order to boot from SSD"