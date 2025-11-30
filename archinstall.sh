#!/bin/bash
# archinstall.sh - A simple Arch Linux installation script

set -e

# -------------------------------------------------------------
# Variables & Settings
# -------------------------------------------------------------
wifi_password=""
wifi_connection_name=""
wifi_station="wlan0"
hostname="archlinux"
username=""
keymap="de-latin1"
locale="en_US.UTF-8 UTF-8"
locale_conf="en_US.UTF-8"
timezone="Europe/Zagreb"
device=""

##################################################################
#
# Start Installation Process
#
##################################################################
install() {
    echo "Starting Arch Linux installation..."
    
    initialize
    partition_disk
    install_base_system
    configure_system
    post_installation
    finalize_installation

    echo "Installation complete! Please reboot."
}

##################################################################
#
# Initialize keymap, connect to wi-fi and choose installation 
# disk.
#
##################################################################
initialize() {
    loadkeys $keymap
    
    if [[ -n "$wifi_connection_name" && -n "$wifi_password" ]]; then
        iwctl --passphrase "$wifi_password" station "$wifi_station" connect "$wifi_connection_name"
    fi

    timedatectl

    clear

    echo "Available disks:"
    lsblk
    read -p "Where do you want to install Arch Linux? This cannot be undone! (e.g., /dev/sda): " device
}

##################################################################
#
# Partition the disk using parted and format partitions.
#
##################################################################
partition_disk() {
    echo "Partitioning disk and formatting partitions..."

    if [[ $device == *"nvme"* ]]; then
        partition1="${device}p1"
        partition2="${device}p2"
        partition3="${device}p3"
        partition4="${device}p4"
    else
        partition1="${device}1"
        partition2="${device}2"
        partition3="${device}3"
        partition4="${device}4"
    fi
    
    parted -s "$device" mklabel gpt
    parted -s "$device" mkpart boot fat32 1MiB 1GiB
    parted -s "$device" mkpart swap linux-swap 1GiB 16GiB
    parted -s "$device" mkpart root ext4 16GiB 76GiB
    parted -s "$device" mkpart home ext4 76GiB 100%
    parted -s "$device" set 1 esp on
    parted -s "$device" set 1 boot on

    mkfs.fat -F 32 "$partition1"
    mkswap "$partition2"
    mkfs.ext4 "$partition3"
    mkfs.ext4 "$partition4"

    echo "Mounting partitions..."
    
    mount $partition3 /mnt
    mount --mkdir $partition1 /mnt/boot
    mount --mkdir $partition4 /mnt/home
    swapon $partition2
}

##################################################################
#
# Install base system and essential packages.
#
##################################################################
install_base_system() {
    echo "Installing base system..."
    
    pacstrap -K /mnt base linux linux-firmware linux-headers sudo nano amd-ucode intel-ucode firewalld grub efibootmgr networkmanager base-devel sof-firmware bluez bluez-utils
}

##################################################################
#
# Configure system: fstab, timezone, localization, users, etc.
#
##################################################################
configure_system() {
    echo "Configuring system..."
    
    generate_fstab
    configure_locale
    configure_users
    configure_bootloader
    enable_services
}

##################################################################
#
# Generate fstab file.
#
##################################################################
generate_fstab() {
    echo "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

##################################################################
#
# Configure timezone, localization, and keymap.
#
##################################################################
configure_locale () {
    arch-chroot /mnt /bin/bash <<EOF
echo "Configuring timezone..."
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

echo "Configuring localization..."
echo "$locale" >> /etc/locale.gen
locale-gen
echo "LANG=$locale_conf" > /etc/locale.conf
echo "KEYMAP=$keymap" > /etc/vconsole.conf
EOF
}

##################################################################
#
# Configure hostname and users.
#
##################################################################
configure_users() {
    echo "Configuring users..."
    
    arch-chroot /mnt /bin/bash <<EOF
echo "Configuring hostname..."
echo "$hostname" > /etc/hostname

useradd -m -G wheel,storage,power,video,plugdev -s /bin/bash $username
EOF

    echo "Configuring users..."

    echo "Set root password:"
    arch-chroot /mnt passwd

    echo "Set password for user $username:"
    arch-chroot /mnt passwd "$username"
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
}

##################################################################
#
# Configure and install bootloader.
#
##################################################################
configure_bootloader() {
    echo "Configuring bootloader..."
    
    arch-chroot /mnt /bin/bash <<EOF
echo "Configuring bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

##################################################################
#
# Enable essential services.
#
##################################################################
enable_services() {
    echo "Enabling services..."
    
    arch-chroot /mnt /bin/bash <<EOF
systemctl enable NetworkManager
systemctl enable bluetooth.service
systemctl enable firewalld
EOF
}

##################################################################
#
# Post-installation: Install additional packages and enable them.
#
##################################################################
post_installation() {
    echo "Performing post-installation steps..."
    
    arch-chroot /mnt /bin/bash <<EOF
echo "Installing additional packages..."
pacman -S --noconfirm plasma-meta kde-system-meta kde-utilities-meta kde-multimedia-meta sddm kdeconnect gwenview
systemctl enable sddm.service

pacman -S --noconfirm fuse2 git qemu-full libvirt virt-manager java-runtime-common nodejs npm cups cups-pdf ffmpeg gstreamer gst-plugins-base gst-plugins-good gst-libav libreoffice-still rsync power-profiles-daemon exfatprogs btrfs-progs ntfs-3g smartmontools lm_sensors docker docker-buildx docker-compose

systemctl enable libvirtd.socket
echo "user = \"$username\"" >> /etc/libvirt/qemu.conf
echo "group = \"libvirt\"" >> /etc/libvirt/qemu.conf

systemctl restart libvirtd
systemctl enable docker.socket

usermod -a -G libvirt $username
usermod -a -G docker $username
EOF
}

finalize_installation() {
    echo "Finalizing installation..."
    
    umount -R /mnt
    reboot
}

install