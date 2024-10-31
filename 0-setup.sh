#!/bin/bash


clear
loadkeys trq
setfont iso09.16  
set -e

# Kullanıcı bilgileri
read -p "Ağda bilgisayarınızın adını benzersiz kılacak bir makine adı belirleyiniz: " [  -z "$HOSTNAME" ] && HOSTNAME="HUHU"

echo "--------------------------------"
echo $HOSTNAME

LOCALE = "tr_TR.UTF-8"
read -p "Dil seçimi yaparak ilerleyiniz: (Örn., tr_TR.UTF-8): " LOCALE

TIMEZONE = "Europe/Istanbul"
read -p "Saat dilimini girin: (Örn., Europe/Istanbul " TIMEZONE

read -p "Yeni oluşacak hesap için kullanıcı adı belirleyiniz. " USER_NAME

# Şifre belirleme
read -s -p "${USER_NAME} kullanıcısı için parola belirleyiniz.: " USER_PASSWORD
echo
read -s -p "Parolayı doğrula: " USER_PASSWORD_CONFIRM
echo
if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
  echo "Parolalar eşleşmiyor!"
  exit 1
fi


# Sistem saatini güncelle
timedatectl set-ntp true

# En hızlı indirme bağlantılarını seç
#pacman -Sy --noconfirm reflector
#reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist





# Bölümleri biçimlendir
read -p "EFI diski girin (Örn., sda1): " EFIBOLUMU
read -p "Arch Linux'un kurulacağı diski girin (Örn., sda2): " BTRFSBOLUMU

mkfs.btrfs -f /dev/${BTRFSBOLUMU}
mkfs.vfat -F32 /dev/${EFIBOLUMU}

# Btrfs alt birimlerini oluştur
mount /dev/${BTRFSBOLUMU} /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Bölmeleri monte edin
mount -o noatime,compress=zstd,subvol=@ /dev/${BTRFSBOLUMU} /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/${BTRFSBOLUMU} /mnt/home
mount -o noatime,compress=zstd,subvol=@var /dev/${BTRFSBOLUMU} /mnt/var
mount -o noatime,compress=zstd,subvol=@snapshots /dev/${BTRFSBOLUMU} /mnt/.snapshots
mount /dev/${EFIBOLUMU} /mnt/boot

# Temel paketleri yükleyin
pacstrap /mnt base base-devel linux-lts linux-firmware btrfs-progs zramswap
#pacstrap /mnt base linux linux-lts linux-firmware util-linux sudo btrfs-progs intel-ucode tpm2-tools clevis lvm2 grub grub-efi-x86_64 efibootmgr zramswap

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
arch-chroot /mnt /bin/bash <<EOF

# Zaman dilimini ayarlayın
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Yerel ayarı ayarlayın
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Ana makine adını ayarla
echo "${HOSTNAME}" > /etc/hostname

# Hosts dosyasını yapılandırın
cat <<EOT > /etc/hosts
   localhost
::1         localhost
   ${HOSTNAME}.localdomain ${HOSTNAME}
EOT

# Initramfs
cat <<EOT > /etc/mkinitcpio.conf
MODULES=(btrfs tpm2)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf block encrypt filesystems)
EOT

mkinitcpio -P

# Set root password
echo "root:${USER_PASSWORD}" | chpasswd -e

# Yeni bir kullanıcı oluşturun ve şifreyi ayarlayın
useradd -m -G wheel -s /bin/bash ${USER_NAME}
echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd

# Yeni kullanıcıya sudo ayrıcalıkları verin
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Paralel indirmeleri etkinleştir
sed -Ei 's/^#(ParallelDownloads.+)/\1/' /etc/pacman.conf

# Ek paketleri yükleyin (Kurulmasını istediğiniz)
pacman -S --noconfirm grub
# pacman -S --noconfirm grub efibootmgr networkmanager network-manager-applet dialog wpa_supplicant mtools dosfstools reflector base-devel linux-headers avahi xdg-user-dirs xdg-utils gvfs gvfs-smb nfs-utils inetutils dnsutils bluez bluez-utils alsa-utils pipewire pipewire-alsa pipewire-pulse pipewire-jack bash-completion openssh timeshift rsync acpi acpi_call tlp dnsmasq ipset ufw flatpak sof-firmware nss-mdns acpid os-prober ntfs-3g wget git gcc neovim btop hyprland waybar xdg-desktop-portal xdg-desktop-portal-hyprland kitty polkit-kde-agent qt5-wayland qt6-wayland rofi-wayland firefox vlc obs-studio grim slurp

# Servisleri etkinleştir
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sshd
systemctl enable avahi-daemon
systemctl enable tlp
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable ufw
systemctl enable acpid

# ZRAM'ı yapılandırın
cat <<EOT > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOT

# GRUB'u kurun
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg


# root hesabını kilitle
# passwd -l root

EOF

# Dosya sistemlerini ayırın
umount -R /mnt



# Yeniden başlat
echo "Kurulum tamamlandı. Yeniden başlatılıyor..."
sleep 3
reboot
