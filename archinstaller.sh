#!/usr/bin/env bash

# Script to install ArchLinux with gnome in a single drive
# TO DO: add option for amd microcode
#	 set silent systemd boot
#	 set firewall 
#	 set encryption of home dir
#	 complete network configuration
#	 fine tune selection of software

# set variables
lsblk
echo "Select drive for instalation:"
read drive
echo "$drive chosen."
echo "Enter hostname:"
read hostname
echo "Enter username:"
read username
echo "Enter user password:"
read -s password

# install preparations
timedatectl set-ntp true
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring
sed -i "s/^#ParallelDownloads/ParallelDownloads/" /etc/pacman.conf 

# partitioning disk
umount -A --recursive /mnt
sgdisk -zap-all $drive
sgdisk -set-alignment=2048 -clear $drive
sgdisk -n 1::+300M --typecode=1:ef00 --change-name=1:'EFIBOOT' $drive
sgdisk -n 2::-0 --typecode=2:8300 --change-name=2:'ROOT' $drive
partprobe $drive

# creating filesystems
mkfs.vfat -F32 -n "EFIBOOT" ${drive}1
mkfs.ext4 -L ROOT ${drive}2

# installing archlinux
mount ${drive}2 /mnt && mount --mkdir ${drive}1 /mnt/boot
reflector --latest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap /mnt base linux linux-firmware vim sudo  --noconfirm --needed

# configuring the system
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt /bin/bash << CHROOT
ln -sf /usr/share/zoneinfo/America/Sao_Paulo
hwclock --systohc --utc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#pt_BR.UTF-8/pt_BR.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
sed -i '/\[multilib\],/Include/''s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring

# network configuration
echo $hostname > /etc/hostname

# adding user
useradd -m -G wheel -s /bin/bash $username
echo "$username:$password" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" | (EDITOR="tee" visudo)
passwd --lock root

# boot loader configuring
uuid=$(blkid | grep ${drive}2 | cut -d ' ' -f 3 | cut -d '"' -f 2)
ptuuid=$(blkid | grep ${drive}2 | cut -d ' ' -f 6 | cut -d '"' -f 2)
cpu_intel=$(lscpu | grep 'Intel' &> /dev/null && echo 'yes' || echo '')

if [[ -n "$cpu_intel" ]]; then
	pacman -S --noconfirm intel-ucode --overwrite=/boot/intel-ucode.img
fi

bootctl install
cat << EOF > /boot/loader/entries/arch.conf
title	Arch Linux
linux	/vmlinuz-linux
initrd	/intel-ucode.img
initrd	/initramfs-linux.img
options	root=UUID=$uuid rw
EOF

cat << EOF > /boot/loader/loader.conf
default arch
timeout 0
editor	no
EOF

sed -i 's#^ \+##g' /boot/loader/entries/arch.conf
sed -i 's#^ \+##g' /boot/loader/loader.conf

# installing graphic drivers
nvidia=$(lspci | grep -e VGA -e 3D | grep 'NVIDIA' 2> /dev/null || echo '')
amd=$(lspci | grep -e VGA -3D | grep 'AMD' 2> /dev/null || echo '')

if [[ -n "$nvidia" ]]; then
	pacman -S --noconfirm --needed nvidia
fi

if [[ -n "$amd" ]]; then
	pacman -S --noconfirm --needed xf86-video-amdgpu
fi

# installing gnome
# pacman -S --noconfirm eog evince file-roller gdm gedit gnome-backgrounds gnome-boxes gnome-calculator \
#  		gnome-characters gnome-color-manager gnome-control-center gnome-font-viewer gnome-keyring \
#  		gnome-music gnome-session gnome-settings-daemon gnome-shell gnome-system-monitor \
#  		gnome-terminal gnome-weather gvfs gvfs-afc gvfs-goa gvfs-google gvfs-gphoto2 gvfs-mtp \
#  		gvfs-nfs gvfs-smb mutter nautilus simple-scan sushi xdg-user-dirs-gtk gnome-tweaks \
#  		celluloid networkmanager
# 
# systemctl enable gdm.service
# systemctl enable NetworkManager.service
# # gsettings set org.gnome.desktop.interface color-scheme prefer-dark
# 
# # installing firefox
# pacman -S --noconfirm firefox firefox-i18n-pt-br firefox-ublock-origin
# 
# # installing libreoffice
# pacman -S --noconfirm libreoffice-fresh
# 
# # installing comunication software
# pacman -S --noconfirm telegram-desktop discord
# 
# # installing fonts
# pacman -S --noconfirm --needed ttf-caladea ttf-carlito ttf-dejavu ttf-liberation ttf-linux-libertine-g \
# 		noto-fonts adobe-source-code-pro-fonts adobe-source-sans-fonts adobe-source-serif-fonts \
# 		ttf-fira-mono ttf-fira-sans
# 
# finishing up
exit
CHROOT
echo "Finished. Reboot now? [Y/n]"
read answer
if [[ ! "$answer" =~ ^(n|N) ]]; then
	reboot
fi
