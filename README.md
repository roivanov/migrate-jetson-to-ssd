# migrate-jetson-to-ssd

# WIP
Once you set up a Jetson Orin Nano or NX to run from an SD card, you may want the option to migrate to an SSD for better performance and storage capacity. While serious developers use an attached PC with SDK Manager and command-line tools to configure their devices and modify them, casual users or those in a pinch might prefer a simpler approach. This toolkit enables you to copy the contents of the SD card to the SSD directly from the Jetson itself, allowing the SSD to serve as the boot medium.

**Note** I've only tried this with one brand of SD card, and a SSD with the same sector size.
The scripts assume your SD card is located at /dev/mmcblk0 and your SSD is /dev/nvme0n1. Command line flags allow you to change that (-h for help).
I'm using the 2280 slot for the SSD. my understanding is that the 2230 slot is /dev/nvme0n2, but is something you will need to check.

## Features
This is a three step process:
- **Partition Copying**: Copy the partition structure from the SD card to the SSD.
- **Data Cloning**: Clone data from the SD card partitions to the SSD partitions.
- **Boot Configuration**: Modify system files to enable the Jetson Developer Kit to boot from the SSD.

## Requirements
- A NVIDIA Jetson Developer Kit with SSD capabilities. It's only been tested on JetPack 6 machines.
- A running system on an SD card.
- An SSD with a larger capacity than the SD card.
- Unformatted SSDs with no partitions appear to work best
- Root privileges to execute the scripts.
- The SSD cannot be mounted when preparing

## Included Scripts
### 1. `make_partitions.sh`
This script copies the partition structure from the SD card to the SSD.

### 2. `copy_partitions.sh`
This script copies the data from the SD card partitions to the corresponding SSD partitions.

### 3. `configure_ssd_boot.sh`
This script modifies system configuration files on the SSD to enable the Jetson Developer Kit to boot from the SSD. It updates:
- `/boot/extlinux/extlinux.conf` to set the SSD's root partition.
- `/etc/fstab` to match the SSD's UUID for system mounts.

## Usage
### Step 1: CopyMake Partition Structure
Run `make_partitions.sh` to copy the partition structure:
```bash
sudo bash make_partitions.sh
```
### Step 2: Copy Partition Data
Run `copy_partitions.sh` to clone the data:
```bash
sudo  bash copy_partitions.sh 
```
### Step 3: Configure SSD Boot
Run `configure_ssd_boot.sh` to modify the system configuration:
```bash
sudo bash configure_ssd_boot.sh 
```

## Notes
- Ensure the SSD has a larger capacity than the SD card.
- Back up your data before running the scripts.
- After completing all steps, reboot the Jetson Developer Kit to verify that it boots from the SSD. (You may have to change the boot order in the UEFI boot sequence).

## Release
### Initial Release
- December, 2024
- Tested on Jetson Orin Nano Super


## License
This project is licensed under the MIT License.
