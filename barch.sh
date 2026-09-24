#!/bin/bash
###############################################
# name: barch                                 #
# description: a basic arch installer in bash #
# author: passthesh3ll                        #
# license: GPL3                               #
###############################################


# ─── Helpers ──────────────────────────────────────────────────────────────────
set -euo pipefail
LPURPLE='\e[95m'
DPURPLE='\e[35m'
RED='\e[31m'
YELLOW='\e[33m'
NC='\e[0m'
trap 'echo -e "\e[31m[ERROR]\e[0m line $LINENO: $BASH_COMMAND" >&2' ERR
SECONDS=0
step() { echo -e "${DPURPLE}=> $*${NC}"; }
sect() { echo -e "\n${LPURPLE}═══════ [$*] ═══════${NC}"; }

# ─── Installation Variables ───────────────────────────────────────────────────

# disk
DISK="/dev/sda"
LUKS=true
LUKS_PASS="changeme"
LVM=true
FILESYSTEM="ext4"
SWAP="auto"

# system
HOST_NAME="computer"
USER_NAME="user"
USER_PASS="changeme"
ROOT_PASS="changeme"
TIMEZONE="Europe/Rome"
LOCALE="en_GB.UTF-8"
KEYBOARD="us"
MIRRORS="Sweden"
OS_PROBER=false
AUR=true

# hardware
INSTALL_CPU_UCODE=true
INSTALL_GPU_DRIVERS=true
VIRTUALBOX_GUEST_UTILS=false
QEMU_GUEST_UTILS=false

# desktop
DESKTOP="xfce"
THEME="black"
ICONS_PAPIRUS=true
WALLHAVEN="j86lwq"
PACKAGES_REMOVE=(parole xfburn xfce4-screenshooter)
PACKAGES_INSTALL=(mpv flameshot)

# services
BLUETOOTH=true
PRINTING=true
NIGHT_LIGHT=true
NIGHT_LIGHT_LATITUDE="41.9"
NIGHT_LIGHT_LONGITUDE="12.5"


# ═══════════════════════════════════════════════════════════════════════════════
# S T A R T
# ═══════════════════════════════════════════════════════════════════════════════
BR="${LPURPLE}BARCH${NC}${DPURPLE}"
echo
echo -e "${DPURPLE}        ╭─────────╮       ${NC}"
echo -e "${DPURPLE}        │  ${BR}  │       ${NC}"
echo -e "${DPURPLE}        ╰─────────╯       ${NC}"
echo -e "${DPURPLE}       a basic arch       ${NC}"
echo -e "${DPURPLE}     installer in bash    ${NC}\n\n"
# ═══════════════════════════════════════════════════════════════════════════════
# [0.0] CONFIGURATION CHECK
# ═══════════════════════════════════════════════════════════════════════════════
sect "0.0" "Checking Configuration"

CHECK_ERRORS=0
check_ok()   { echo -e "${LPURPLE}[ OK ]${NC} $*"; }
check_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
check_err()  { echo -e "${RED}[FAIL]${NC} $*"; CHECK_ERRORS=$((CHECK_ERRORS + 1)); }

# ─── Environment ──────────────────────────────────────────────────────────────
(( EUID == 0 )) || check_err "the script must be run as root"
[[ -d /sys/firmware/efi ]] || check_err "system is not booted in UEFI mode"
curl -fsS --max-time 3 https://archlinux.org >/dev/null || check_warn "no internet connection"

# ─── Required variables ───────────────────────────────────────────────────────
for VAR in HOST_NAME USER_NAME USER_PASS ROOT_PASS DISK FILESYSTEM SWAP \
           TIMEZONE LOCALE KEYBOARD MIRRORS DESKTOP THEME; do
    [[ -n "${!VAR:-}" ]] || check_err "$VAR is empty"
done

# ─── Disk ─────────────────────────────────────────────────────────────────────
[[ -b "$DISK" ]] || check_err "DISK '$DISK' is not a block device"

# ─── Filesystem ───────────────────────────────────────────────────────────────
[[ "$FILESYSTEM" =~ ^(ext4|btrfs)$ ]] || \
    check_err "FILESYSTEM must be 'ext4' or 'btrfs' (got '$FILESYSTEM')"

# ─── Swap ─────────────────────────────────────────────────────────────────────
[[ "$SWAP" == "auto" || "$SWAP" == "false" || "$SWAP" =~ ^[0-9]+$ ]] || \
    check_err "SWAP must be 'auto', 'false' or a size in MiB (got '$SWAP')"

# ─── Desktop ──────────────────────────────────────────────────────────────────
[[ "$DESKTOP" =~ ^(xfce|kde|gnome|cinnamon|mate|lxqt|none)$ ]] || \
    check_err "unknown DESKTOP '$DESKTOP' (xfce|kde|gnome|cinnamon|mate|lxqt|none)"

# ─── Theme ────────────────────────────────────────────────────────────────────
[[ "$THEME" =~ ^(default|dark|black)$ ]] || \
    check_err "THEME must be 'default', 'dark' or 'black' (got '$THEME')"
[[ "$DESKTOP" == "none" && ( "$THEME" != "default" || "$ICONS_PAPIRUS" == true ) ]] && \
    check_warn "theme/icons requested but DESKTOP=none: they will not be applied"

# ─── Wallpaper ────────────────────────────────────────────────────────────────
[[ "$WALLHAVEN" == "none" || "$WALLHAVEN" =~ ^[a-z0-9]{6}$ ]] || \
    check_err "WALLHAVEN must be 'none' or a 6-character wallhaven code (got '$WALLHAVEN')"
[[ "$WALLHAVEN" != "none" && "$DESKTOP" == "none" ]] && \
    check_warn "WALLHAVEN is set but DESKTOP=none: no wallpaper will be applied"

# ─── Username ─────────────────────────────────────────────────────────────────
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || check_err "invalid USER_NAME '$USER_NAME'"

# ─── Booleans ─────────────────────────────────────────────────────────────────
for VAR in LUKS LVM ICONS_PAPIRUS BLUETOOTH PRINTING NIGHT_LIGHT \
           INSTALL_CPU_UCODE INSTALL_GPU_DRIVERS VIRTUALBOX_GUEST_UTILS \
           QEMU_GUEST_UTILS OS_PROBER AUR; do
    [[ "${!VAR:-}" =~ ^(true|false)$ ]] || \
        check_err "$VAR must be 'true' or 'false' (got '${!VAR:-}')"
done

# ─── LUKS / LVM ───────────────────────────────────────────────────────────────
if [[ "$LUKS" == true ]]; then
    [[ -n "$LUKS_PASS" ]] || check_err "LUKS_PASS is empty but LUKS=true"
else
    check_warn "LUKS=false: the disk will not be encrypted"
fi

# ─── Timezone / locale / keymap ───────────────────────────────────────────────
[[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]] || check_err "TIMEZONE '$TIMEZONE' not found"
grep -qE "^#?${LOCALE} " /etc/locale.gen || check_warn "LOCALE '$LOCALE' not listed in /etc/locale.gen"
localectl list-keymaps 2>/dev/null | grep -qx "$KEYBOARD" || check_warn "KEYBOARD '$KEYBOARD' not found"

# ─── Night light coordinates ──────────────────────────────────────────────────
if [[ "$NIGHT_LIGHT" == true ]]; then
    [[ "$NIGHT_LIGHT_LATITUDE"  =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || \
        check_err "NIGHT_LIGHT_LATITUDE is not numeric ('$NIGHT_LIGHT_LATITUDE')"
    [[ "$NIGHT_LIGHT_LONGITUDE" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || \
        check_err "NIGHT_LIGHT_LONGITUDE is not numeric ('$NIGHT_LIGHT_LONGITUDE')"
fi

# ─── Default passwords ────────────────────────────────────────────────────────
[[ "$USER_PASS" == changeme || "$ROOT_PASS" == changeme || \
   ( "$LUKS" == true && "$LUKS_PASS" == changeme ) ]] && \
    check_warn "one or more passwords are still 'changeme'"

# ─── Result ───────────────────────────────────────────────────────────────────
if (( CHECK_ERRORS > 0 )); then
    echo -e "${RED}[ERROR]${NC} ${CHECK_ERRORS} configuration problem(s) found, aborting" >&2
    exit 1
fi

# ─── CPU detection ────────────────────────────────────────────────────────────
if [[ "$INSTALL_CPU_UCODE" == true ]]; then
    step "[0.1] Detecting CPU"
    case $(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}') in
        GenuineIntel) UCODE_PACKAGES=(intel-ucode) ;;
        AuthenticAMD) UCODE_PACKAGES=(amd-ucode) ;;
        *)            UCODE_PACKAGES=() ;;
    esac
    echo "-> microcode: ${UCODE_PACKAGES[*]:-none}"
else
    UCODE_PACKAGES=()
    echo "-> cpu microcode: disabled by INSTALL_CPU_UCODE=false"
fi

# ─── GPU detection ────────────────────────────────────────────────────────────
if [[ "$INSTALL_GPU_DRIVERS" == true ]]; then
    step "[0.2] Detecting GPU"
    GPU_INFO=$(lspci | grep -Ei 'vga|3d|display' || true)
    if   grep -qi 'nvidia'    <<<"$GPU_INFO"; then GPU_DRIVER="nvidia"
    elif grep -qiE 'amd|ati'  <<<"$GPU_INFO"; then GPU_DRIVER="amd"
    elif grep -qi 'intel'     <<<"$GPU_INFO"; then GPU_DRIVER="intel"
    else GPU_DRIVER="generic"
    fi
    [[ "$(systemd-detect-virt)" != "none" ]] && GPU_DRIVER="vm"

    case "$GPU_DRIVER" in
        intel)  GPU_PACKAGES=(mesa vulkan-intel intel-media-driver) ;;
        amd)    GPU_PACKAGES=(mesa vulkan-radeon libva-mesa-driver) ;;
        nvidia) GPU_PACKAGES=(mesa) ;;
        *)      GPU_PACKAGES=(mesa) ;;
    esac
    echo "-> gpu: $GPU_DRIVER"
else
    GPU_DRIVER="none"
    GPU_PACKAGES=()
    [[ "$DESKTOP" != "none" ]] && \
        echo -e "${YELLOW}[WARN]${NC} DESKTOP=$DESKTOP but GPU drivers disabled: the GUI may not work"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [1.0] DISK PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
sect "1.0" "Formatting Disk"

# ─── System clock ─────────────────────────────────────────────────────────────
step "[1.1] Syncing system clock"
timedatectl set-ntp true

# ─── Leftover cleanup ─────────────────────────────────────────────────────────
step "[1.2] Cleaning up previous installations"
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
vgchange -an 2>/dev/null || true
cryptsetup close cryptlvm 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true
wipefs -af "$DISK"

# ─── Disk partitioning ────────────────────────────────────────────────────────
step "[1.3] Partitioning $DISK"
if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
    PART_BOOT="${DISK}p1"; PART_ROOT="${DISK}p2"
else
    PART_BOOT="${DISK}1";  PART_ROOT="${DISK}2"
fi
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 1025MiB 100%
udevadm settle
wipefs -af "$PART_BOOT" "$PART_ROOT"

# ─── Device mapping ───────────────────────────────────────────────────────────
CRYPT_NAME="cryptroot"
[[ "$LVM" == true ]] && CRYPT_NAME="cryptlvm"

# ─── LUKS encryption ──────────────────────────────────────────────────────────
if [[ "$LUKS" == true ]]; then
    step "[1.4] Setting up LUKS encryption"
    printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --batch-mode --key-file - "$PART_ROOT"
    printf '%s' "$LUKS_PASS" | cryptsetup open --key-file - "$PART_ROOT" "$CRYPT_NAME"
    ROOT_BASE="/dev/mapper/${CRYPT_NAME}"
else
    echo "-> luks encryption: disabled by LUKS=false"
    ROOT_BASE="$PART_ROOT"
fi

# ─── LVM setup ────────────────────────────────────────────────────────────────
if [[ "$LVM" == true ]]; then
    step "[1.5] Setting up LVM"
    pvcreate "$ROOT_BASE"
    vgcreate vg0 "$ROOT_BASE"
    lvcreate -l 100%FREE -n root vg0
    ROOT_DEVICE="/dev/vg0/root"
else
    echo "-> lvm: disabled by LVM=false"
    ROOT_DEVICE="$ROOT_BASE"
fi

# ─── Filesystems ──────────────────────────────────────────────────────────────
step "[1.6] Formatting filesystems"
mkfs.fat -F32 "$PART_BOOT"
case "$FILESYSTEM" in
    ext4)  mkfs.ext4 -F "$ROOT_DEVICE" ;;
    btrfs) mkfs.btrfs -f "$ROOT_DEVICE" ;;
esac

# ─── Mounting ─────────────────────────────────────────────────────────────────
step "[1.7] Mounting filesystems"
case "$FILESYSTEM" in
    ext4)
        mount "$ROOT_DEVICE" /mnt
        ;;
    btrfs)
        mount "$ROOT_DEVICE" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@pkg
        btrfs subvolume create /mnt/@log
        btrfs subvolume create /mnt/@swap
        umount /mnt
        BTRFS_OPTS="noatime,compress=zstd"
        mount -o "${BTRFS_OPTS},subvol=@" "$ROOT_DEVICE" /mnt
        mkdir -p /mnt/home /mnt/var/cache/pacman/pkg /mnt/var/log /mnt/swap
        mount -o "${BTRFS_OPTS},subvol=@home" "$ROOT_DEVICE" /mnt/home
        mount -o "${BTRFS_OPTS},subvol=@pkg"  "$ROOT_DEVICE" /mnt/var/cache/pacman/pkg
        mount -o "${BTRFS_OPTS},subvol=@log"  "$ROOT_DEVICE" /mnt/var/log
        mount -o "noatime,subvol=@swap"       "$ROOT_DEVICE" /mnt/swap
        chattr +C /mnt/swap
        ;;
esac
mount --mkdir "$PART_BOOT" /mnt/boot

# ═══════════════════════════════════════════════════════════════════════════════
# [2.0] BASE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════
sect "2.0" "Installing Base OS"

# ─── Pacman mirrors ───────────────────────────────────────────────────────────
step "[2.1] Configuring pacman mirrors"
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
reflector \
    --country "$MIRRORS" \
    --age 12 \
    --protocol https \
    --latest 20 \
    --sort rate \
    --connection-timeout 5 \
    --download-timeout 5 \
    --save /etc/pacman.d/mirrorlist || true
if [[ ! -s /etc/pacman.d/mirrorlist ]]; then
    echo -e "${YELLOW}[WARN]${NC} reflector produced no mirrors, restoring default mirrorlist"
    cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
fi
rm -f /etc/pacman.d/mirrorlist.bak

# ─── Base system ──────────────────────────────────────────────────────────────
step "[2.2] Installing base system"
FS_PACKAGES=()
[[ "$FILESYSTEM" == btrfs ]] && FS_PACKAGES=(btrfs-progs)
SWAP_PACKAGES=()
[[ "$SWAP" != false ]] && SWAP_PACKAGES=(zram-generator)
LUKS_PACKAGES=()
[[ "$LUKS" == true ]] && LUKS_PACKAGES=(cryptsetup)
LVM_PACKAGES=()
[[ "$LVM" == true ]] && LVM_PACKAGES=(lvm2)
pacstrap -K /mnt \
    base base-devel linux linux-headers linux-firmware dkms \
    grub efibootmgr networkmanager pacman-contrib nano git vim sudo \
    "${UCODE_PACKAGES[@]}" "${FS_PACKAGES[@]}" "${SWAP_PACKAGES[@]}" \
    "${LUKS_PACKAGES[@]}" "${LVM_PACKAGES[@]}" cronie lm_sensors

# ─── Pacman configuration ─────────────────────────────────────────────────────
step "[2.3] Configuring pacman"
sed -i \
    -e 's|^#Color$|Color\nILoveCandy|' \
    -e 's|^#CheckSpace$|CheckSpace|' \
    -e 's|^#ParallelDownloads = .*|ParallelDownloads = 5|' \
    -e 's|^#DownloadUser = alpm$|DownloadUser = alpm|' \
    /mnt/etc/pacman.conf

# ─── ZRAM ─────────────────────────────────────────────────────────────────────
if [[ "$SWAP" != false ]]; then
    step "[2.4] Enabling ZRAM"
    cat <<EOF > /mnt/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
fi

# ─── Swap file ────────────────────────────────────────────────────────────────
if [[ "$SWAP" != false ]]; then
    step "[2.5] Enabling swap file"
    if [[ "$SWAP" == "auto" ]]; then
        RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
        if   (( RAM_MB <= 2048  )); then SWAP_MB=$((RAM_MB * 2))
        elif (( RAM_MB <= 8192  )); then SWAP_MB=$RAM_MB
        elif (( RAM_MB <= 65536 )); then SWAP_MB=$((RAM_MB / 2))
        else                            SWAP_MB=4096
        fi
    else
        SWAP_MB=$SWAP
    fi
    echo "-> swapfile: ${SWAP_MB} MiB"
    case "$FILESYSTEM" in
        ext4)
            dd if=/dev/zero of=/mnt/swapfile bs=1M count="$SWAP_MB" status=progress
            chmod 600 /mnt/swapfile
            mkswap /mnt/swapfile
            swapon -p 10 /mnt/swapfile
            ;;
        btrfs)
            btrfs filesystem mkswapfile --size "${SWAP_MB}m" --uuid clear /mnt/swap/swapfile
            swapon -p 10 /mnt/swap/swapfile
            ;;
    esac
fi

# ─── fstab ────────────────────────────────────────────────────────────────────
step "[2.6] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# ─── Base services ────────────────────────────────────────────────────────────
step "[2.7] Enabling base services"
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable cronie.service
arch-chroot /mnt systemctl enable fstrim.timer
arch-chroot /mnt systemctl enable systemd-timesyncd.service

# ═══════════════════════════════════════════════════════════════════════════════
# [3.0] SYSTEM CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
sect "3.0" "Configuring System"

# ─── Timezone ─────────────────────────────────────────────────────────────────
step "[3.1] Configuring timezone"
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
arch-chroot /mnt hwclock --systohc

# ─── Localization ─────────────────────────────────────────────────────────────
step "[3.2] Configuring localization"
if [[ "$LOCALE" == *.UTF-8 ]]; then
    LOCALE_GEN="${LOCALE} UTF-8"
else
    LOCALE_GEN="${LOCALE%.*} ${LOCALE##*.}"
fi
printf '%s\n' "${LOCALE_GEN}" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
printf '%s\n' "LANG=${LOCALE}"      > /mnt/etc/locale.conf
printf '%s\n' "KEYMAP=${KEYBOARD}"  > /mnt/etc/vconsole.conf

# ─── Hostname and hosts ───────────────────────────────────────────────────────
step "[3.3] Setting hostname and hosts"
printf '%s\n' "${HOST_NAME}" > /mnt/etc/hostname
printf '%s\n' \
    "127.0.0.1   localhost" \
    "::1         localhost" \
    "127.0.1.1   ${HOST_NAME}.localdomain ${HOST_NAME}" \
    > /mnt/etc/hosts

# ─── mkinitcpio ───────────────────────────────────────────────────────────────
step "[3.4] Configuring mkinitcpio hooks"
MKINITCPIO_HOOKS="base udev autodetect microcode modconf kms keyboard keymap consolefont block"
[[ "$LUKS" == true ]] && MKINITCPIO_HOOKS="${MKINITCPIO_HOOKS} encrypt"
[[ "$LVM" == true ]]  && MKINITCPIO_HOOKS="${MKINITCPIO_HOOKS} lvm2"
MKINITCPIO_HOOKS="${MKINITCPIO_HOOKS} filesystems fsck"
arch-chroot /mnt sed -i \
    "s|^HOOKS=(.*|HOOKS=(${MKINITCPIO_HOOKS})|" \
    /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# ═══════════════════════════════════════════════════════════════════════════════
# [4.0] BOOTLOADER
# ═══════════════════════════════════════════════════════════════════════════════
sect "4.0" "Configuring Bootloader"

# ─── GRUB ─────────────────────────────────────────────────────────────────────
step "[4.1] Configuring GRUB"
KERNEL_PARAMS="loglevel=3 quiet"
if [[ "$LUKS" == true ]]; then
    LUKS_UUID=$(blkid -s UUID -o value "$PART_ROOT")
    KERNEL_PARAMS="${KERNEL_PARAMS} cryptdevice=UUID=${LUKS_UUID}:${CRYPT_NAME}:allow-discards"
fi
if [[ "$LUKS" == false && "$LVM" == false ]]; then
    KERNEL_PARAMS="${KERNEL_PARAMS} root=UUID=$(blkid -s UUID -o value "$ROOT_DEVICE")"
else
    KERNEL_PARAMS="${KERNEL_PARAMS} root=${ROOT_DEVICE}"
fi
[[ "$SWAP" != false ]]       && KERNEL_PARAMS="${KERNEL_PARAMS} zswap.enabled=0"
[[ "$FILESYSTEM" == btrfs ]] && KERNEL_PARAMS="${KERNEL_PARAMS} rootflags=subvol=@"
arch-chroot /mnt sed -i \
    "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${KERNEL_PARAMS}\"|" \
    /etc/default/grub
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
if [[ "$OS_PROBER" == true ]]; then
    arch-chroot /mnt pacman -S --noconfirm os-prober
    arch-chroot /mnt sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# ═══════════════════════════════════════════════════════════════════════════════
# [5.0] USERS
# ═══════════════════════════════════════════════════════════════════════════════
sect "5.0" "Configuring Users"

# ─── Users and sudo ───────────────────────────────────────────────────────────
step "[5.1] Setting up users and sudo"
printf '%s\n' "root:${ROOT_PASS}" | arch-chroot /mnt chpasswd
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USER_NAME}"
printf '%s\n' "${USER_NAME}:${USER_PASS}" | arch-chroot /mnt chpasswd
printf '%s\n' "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10-wheel

# ═══════════════════════════════════════════════════════════════════════════════
# [6.0] DESKTOP ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════════
sect "6.0" "Installing Desktop Environment"

# ─── DE packages and display manager ──────────────────────────────────────────
DE_PACKAGES=()
SESSION_PACKAGES=()
DE_DM=""
case "$DESKTOP" in
    # ─── XFCE ───────────────────────────────────────────────────────────────
    xfce)
        DE_PACKAGES=(
            xfce4 xfce4-goodies
            lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
            xarchiver
            network-manager-applet pavucontrol
            gnome-keyring
            xdg-desktop-portal-gtk
        )
        DE_DM="lightdm"
        SESSION_PACKAGES=(xorg-server)
        ;;
    # ─── KDE Plasma ─────────────────────────────────────────────────────────
    kde)
        DE_PACKAGES=(
            plasma-desktop kdeplasma-addons
            breeze
            plasma-nm plasma-pa kscreen powerdevil
            dolphin konsole kate ark gwenview okular spectacle
            sddm sddm-kcm layer-shell-qt
            xdg-desktop-portal-kde
        )
        DE_DM="sddm"
        SESSION_PACKAGES=(xorg-xwayland)
        ;;
    # ─── GNOME ──────────────────────────────────────────────────────────────
    gnome)
        DE_PACKAGES=(
            gnome
            gdm
            file-roller
        )
        DE_DM="gdm"
        SESSION_PACKAGES=(xorg-xwayland)
        ;;
    # ─── Cinnamon ───────────────────────────────────────────────────────────
    cinnamon)
        DE_PACKAGES=(
            cinnamon
            lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
            xed xviewer xreader
            gnome-terminal
            file-roller
            gnome-keyring
            xdg-desktop-portal-gtk
        )
        DE_DM="lightdm"
        SESSION_PACKAGES=(xorg-server)
        ;;
    # ─── MATE ───────────────────────────────────────────────────────────────
    mate)
        DE_PACKAGES=(
            mate mate-extra
            lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
            network-manager-applet pavucontrol
            gnome-keyring
            xdg-desktop-portal-gtk
        )
        DE_DM="lightdm"
        SESSION_PACKAGES=(xorg-server)
        ;;
    # ─── LXQt ───────────────────────────────────────────────────────────────
    lxqt)
        DE_PACKAGES=(
            lxqt breeze-icons
            lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
            network-manager-applet
            gnome-keyring
            xdg-desktop-portal-gtk
            xorg-xrdb
        )
        DE_DM="lightdm"
        SESSION_PACKAGES=(xorg-server)
        ;;
    # ─── Headless ───────────────────────────────────────────────────────────
    none)
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown DESKTOP: '$DESKTOP'" >&2
        exit 1
        ;;
esac

# ─── Nouveau X11 driver ───────────────────────────────────────────────────────
if [[ "$GPU_DRIVER" == "nvidia" && "${SESSION_PACKAGES[*]:-}" == *xorg-server* ]]; then
    SESSION_PACKAGES+=(xf86-video-nouveau)
fi

# ─── GPU drivers ──────────────────────────────────────────────────────────────
if (( ${#GPU_PACKAGES[@]} > 0 )); then
    step "[6.1] Installing GPU drivers"
    arch-chroot /mnt pacman -S --noconfirm "${GPU_PACKAGES[@]}"
fi

if [[ "$DESKTOP" != "none" ]]; then

    # ─── Common packages ──────────────────────────────────────────────────────
    COMMON_PACKAGES=(
        noto-fonts noto-fonts-cjk noto-fonts-emoji otf-font-awesome ttf-dejavu ttf-liberation
        pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber
        gvfs gvfs-mtp gvfs-smb udisks2
        unzip zip unrar p7zip lzip lrzip lzop unarchiver
        xdg-user-dirs
    )

    step "[6.2] Installing common desktop packages"
    arch-chroot /mnt pacman -S --noconfirm "${COMMON_PACKAGES[@]}" "${SESSION_PACKAGES[@]}"

    step "[6.3] Installing $DESKTOP"
    arch-chroot /mnt pacman -S --noconfirm "${DE_PACKAGES[@]}"

    # ─── Unwanted packages ────────────────────────────────────────────────────
    if (( ${#PACKAGES_REMOVE[@]} > 0 )) && [[ "$DESKTOP" == "xfce" ]]; then
        step "[6.4] Removing unwanted packages"
        arch-chroot /mnt pacman -Rns --noconfirm "${PACKAGES_REMOVE[@]}" || true
    fi

    # ─── Extra packages ───────────────────────────────────────────────────────
    if (( ${#PACKAGES_INSTALL[@]} > 0 )); then
        step "[6.5] Installing extra packages"
        arch-chroot /mnt pacman -S --noconfirm "${PACKAGES_INSTALL[@]}"
    fi
fi

# ─── Bluetooth ────────────────────────────────────────────────────────────────
if [[ "$BLUETOOTH" == true ]]; then
    step "[6.6] Installing Bluetooth stack"
    arch-chroot /mnt pacman -S --noconfirm bluez bluez-utils
    if [[ "$DESKTOP" != "none" ]]; then
        case "$DESKTOP" in
            xfce|cinnamon|mate|lxqt)
                arch-chroot /mnt pacman -S --noconfirm blueman
                ;;
            kde)
                arch-chroot /mnt pacman -S --noconfirm bluedevil
                ;;
        esac
    fi
    arch-chroot /mnt systemctl enable bluetooth
fi

# ─── Printing ─────────────────────────────────────────────────────────────────
if [[ "$PRINTING" == true && "$DESKTOP" != "none" ]]; then
    step "[6.7] Installing printing support"
    arch-chroot /mnt pacman -S --noconfirm cups system-config-printer
    arch-chroot /mnt systemctl enable cups
fi

# ─── Hardware sensors ─────────────────────────────────────────────────────────
step "[6.8] Detecting hardware sensors"
arch-chroot /mnt sensors-detect --auto || true

# ─── Display manager ──────────────────────────────────────────────────────────
if [[ -n "$DE_DM" ]]; then
    step "[6.9] Enabling $DE_DM"

    if [[ "$DE_DM" == "sddm" ]]; then
        mkdir -p /mnt/etc/sddm.conf.d
        cat <<'EOF' > /mnt/etc/sddm.conf.d/10-wayland.conf
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
    fi

    arch-chroot /mnt systemctl enable "$DE_DM"
fi

# ─── Night light ──────────────────────────────────────────────────────────────
if [[ "$NIGHT_LIGHT" == true && "$DESKTOP" != "none" ]]; then
    step "[6.10] Configuring night light"
    case "$DESKTOP" in
        xfce|mate|lxqt)
            arch-chroot /mnt pacman -S --noconfirm redshift
            for HOME_DIR in "/mnt/etc/skel" "/mnt/home/${USER_NAME}"; do
                mkdir -p "$HOME_DIR/.config/redshift"
                cat <<EOF > "$HOME_DIR/.config/redshift/redshift.conf"
[redshift]
temp-day=6500
temp-night=4000
transition=1
location-provider=manual
adjustment-method=randr

[manual]
lat=${NIGHT_LIGHT_LATITUDE}
lon=${NIGHT_LIGHT_LONGITUDE}
EOF
            done
            arch-chroot /mnt chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.config"
            mkdir -p /mnt/etc/xdg/autostart
            cat <<'EOF' > /mnt/etc/xdg/autostart/redshift.desktop
[Desktop Entry]
Type=Application
Name=Redshift
Comment=Adjust screen color temperature
Exec=redshift
X-GNOME-Autostart-enabled=true
EOF
            ;;
        kde)
            cat <<EOF > /mnt/etc/xdg/kwinrc
[NightColor]
Active=true
Mode=Location
Latitude=${NIGHT_LIGHT_LATITUDE}
Longitude=${NIGHT_LIGHT_LONGITUDE}
NightTemperature=4000
EOF
            ;;
        gnome|cinnamon)
            arch-chroot /mnt pacman -S --noconfirm --needed dconf
            mkdir -p /mnt/etc/dconf/profile /mnt/etc/dconf/db/local.d
            cat <<'EOF' > /mnt/etc/dconf/profile/user
user-db:user
system-db:local
EOF
            DCONF_SCHEMA="org/gnome/settings-daemon/plugins/color"
            [[ "$DESKTOP" == "cinnamon" ]] && \
                DCONF_SCHEMA="org/cinnamon/settings-daemon/plugins/color"
            cat <<EOF > /mnt/etc/dconf/db/local.d/01-night-light
[${DCONF_SCHEMA}]
night-light-enabled=true
night-light-schedule-automatic=true
night-light-last-coordinates=(${NIGHT_LIGHT_LATITUDE}, ${NIGHT_LIGHT_LONGITUDE})
night-light-schedule-from=20.0
night-light-schedule-to=6.0
night-light-temperature=uint32 4000
EOF
            arch-chroot /mnt dconf update
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [7.0] WALLPAPER
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$DESKTOP" != "none" && "$WALLHAVEN" != "none" ]]; then
    sect "7.0" "Setting Wallpaper"

    # ─── Download ─────────────────────────────────────────────────────────────
    step "[7.1] Downloading wallpaper '$WALLHAVEN'"
    WALL_TMP=""
    WALL_EXT=""
    for EXT in jpg png; do
        WALL_TMP="/tmp/wallhaven-${WALLHAVEN}.${EXT}"
        if curl -fsSL "https://w.wallhaven.cc/full/${WALLHAVEN:0:2}/wallhaven-${WALLHAVEN}.${EXT}" -o "$WALL_TMP"; then
            WALL_EXT="$EXT"
            break
        fi
        rm -f "$WALL_TMP"
        WALL_TMP=""
    done
    if [[ -z "$WALL_TMP" ]]; then
        echo -e "${RED}[ERROR]${NC} wallpaper '$WALLHAVEN' not found on wallhaven" >&2
        exit 1
    fi

    # ─── Per-DE default wallpaper directory ───────────────────────────────────
    step "[7.2] Saving wallpaper"
    case "$DESKTOP" in
        xfce)     WALL_DIR="/usr/share/backgrounds/xfce" ;;
        kde)      WALL_DIR="/usr/share/wallpapers" ;;
        gnome)    WALL_DIR="/usr/share/backgrounds/gnome" ;;
        cinnamon) WALL_DIR="/usr/share/backgrounds" ;;
        mate)     WALL_DIR="/usr/share/backgrounds/mate" ;;
        lxqt)     WALL_DIR="/usr/share/lxqt/wallpapers" ;;
    esac
    WALL_DEST="${WALL_DIR}/wallhaven-${WALLHAVEN}.${WALL_EXT}"
    mkdir -p "/mnt${WALL_DIR}"
    mv "$WALL_TMP" "/mnt${WALL_DEST}"
    echo "-> wallpaper saved: $WALL_DEST"

    # ─── dconf system defaults ────────────────────────────────────────────────
    DCONF_WALL=false
    case "$DESKTOP" in
        gnome|cinnamon|mate)
            DCONF_WALL=true
            arch-chroot /mnt pacman -S --noconfirm --needed dconf
            mkdir -p /mnt/etc/dconf/profile /mnt/etc/dconf/db/local.d
            cat <<'EOF' > /mnt/etc/dconf/profile/user
user-db:user
system-db:local
EOF
            ;;
    esac

    # ─── Apply as default background ──────────────────────────────────────────
    step "[7.3] Applying wallpaper to $DESKTOP"
    case "$DESKTOP" in
        # ─── XFCE ───────────────────────────────────────────────────────────
        xfce)
            XFDESKTOP="/mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
            if [[ -f "$XFDESKTOP" ]]; then
                sed -i "s|\(name=\"last-image\" type=\"string\" value=\"\)[^\"]*|\1${WALL_DEST}|g" "$XFDESKTOP"
            else
                mkdir -p "$(dirname "$XFDESKTOP")"
                cat <<EOF > "$XFDESKTOP"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${WALL_DEST}"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
            fi
            ;;
        # ─── KDE Plasma ─────────────────────────────────────────────────────
        kde)
            sed -i '/<entry name="Image"/,/<\/entry>/ s|<default>[^<]*</default>|<default>file://'"${WALL_DEST}"'</default>|' \
                "/mnt/usr/share/plasma/wallpapers/org.kde.image/contents/config/main.xml"
            ;;
        # ─── GNOME ──────────────────────────────────────────────────────────
        gnome)
            cat <<EOF > /mnt/etc/dconf/db/local.d/02-wallpaper
[org/gnome/desktop/background]
picture-uri='file://${WALL_DEST}'
picture-uri-dark='file://${WALL_DEST}'
picture-options='zoom'
EOF
            ;;
        # ─── Cinnamon ───────────────────────────────────────────────────────
        cinnamon)
            cat <<EOF > /mnt/etc/dconf/db/local.d/02-wallpaper
[org/cinnamon/desktop/background]
picture-uri='file://${WALL_DEST}'
picture-options='zoom'
EOF
            ;;
        # ─── MATE ───────────────────────────────────────────────────────────
        mate)
            cat <<EOF > /mnt/etc/dconf/db/local.d/02-wallpaper
[org/mate/background]
picture-filename='${WALL_DEST}'
picture-options='zoom'
EOF
            ;;
        # ─── LXQt ───────────────────────────────────────────────────────────
        lxqt)
            mkdir -p /mnt/etc/xdg/pcmanfm-qt/lxqt
            cat <<EOF > /mnt/etc/xdg/pcmanfm-qt/lxqt/settings.conf
[Desktop]
Wallpaper=${WALL_DEST}
WallpaperMode=zoom
EOF
            ;;
    esac

    [[ "$DCONF_WALL" == true ]] && arch-chroot /mnt dconf update
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [8.0] THEMING
# ═══════════════════════════════════════════════════════════════════════════════
DARK_VARIANT=false
[[ "$THEME" == "dark" || "$THEME" == "black" ]] && DARK_VARIANT=true

if [[ "$DESKTOP" != "none" && ( "$DARK_VARIANT" == true || "$ICONS_PAPIRUS" == true ) ]]; then
    sect "8.0" "Applying Themes"

    # ─── Theme packages ───────────────────────────────────────────────────────
    step "[8.1] Installing theme packages"
    THEME_PACKAGES=()
    [[ "$ICONS_PAPIRUS" == true ]] && THEME_PACKAGES+=(papirus-icon-theme)
    if [[ "$DESKTOP" == "kde" ]]; then
        # GTK apps under Plasma follow Breeze-Dark (both for dark and black)
        [[ "$DARK_VARIANT" == true ]] && THEME_PACKAGES+=(breeze-gtk)
    elif [[ "$THEME" == "dark" ]]; then
        THEME_PACKAGES+=(gnome-themes-extra)                       # Adwaita-dark (GTK3)
        [[ "$DESKTOP" == "mate" ]] && THEME_PACKAGES+=(mate-themes) # BlackMATE
    elif [[ "$THEME" == "black" ]]; then
        [[ "$DESKTOP" != "lxqt" ]] && THEME_PACKAGES+=(qt5ct qt6ct)
    fi
    (( ${#THEME_PACKAGES[@]} > 0 )) && \
        arch-chroot /mnt pacman -S --noconfirm "${THEME_PACKAGES[@]}"

    # ─── Icon theme name ──────────────────────────────────────────────────────
    ICON_THEME=""
    if [[ "$ICONS_PAPIRUS" == true ]]; then
        ICON_THEME="Papirus"
        [[ "$DARK_VARIANT" == true ]] && ICON_THEME="Papirus-Dark"
    fi

    # ─── Breeze-Dark-OLED theme (KDE, black only) ─────────────────────────────
    if [[ "$THEME" == "black" && "$DESKTOP" == "kde" ]]; then
        step "[8.2] Installing Breeze-Dark-OLED theme"
        OLED_TMP=$(mktemp -d)
        curl -fsSL "https://raw.githubusercontent.com/RazerPC/Breeze-Dark-OLED/main/Breeze-Dark-OLED.colors" \
            -o "$OLED_TMP/Breeze-Dark-OLED.colors"
        curl -fsSL "https://raw.githubusercontent.com/RazerPC/Breeze-Dark-OLED/main/Breeze-Dark-OLED-Plasma.tar.gz" \
            -o "$OLED_TMP/Breeze-Dark-OLED-Plasma.tar.gz"
        mkdir -p /mnt/usr/share/color-schemes /mnt/usr/share/plasma/desktoptheme
        cp "$OLED_TMP/Breeze-Dark-OLED.colors" /mnt/usr/share/color-schemes/
        tar -xzf "$OLED_TMP/Breeze-Dark-OLED-Plasma.tar.gz" \
            -C /mnt/usr/share/plasma/desktoptheme/
        # the theme targets Plasma 5: bump the API version so Plasma 6 loads it
        OLED_META="/mnt/usr/share/plasma/desktoptheme/Breeze-Dark-OLED-Plasma/metadata.json"
        [[ -f "$OLED_META" ]] && \
            sed -i -E 's/"X-Plasma-API": *"5\.0"/"X-Plasma-API": "6.0"/' "$OLED_META"
        rm -rf "$OLED_TMP"

        # look-and-feel package: this is what Plasma applies on first login
        LNF_DIR="/mnt/usr/share/plasma/look-and-feel/org.kde.breezedark-oled.desktop"
        mkdir -p "${LNF_DIR}/contents/defaults"
        cat <<'EOF' > "${LNF_DIR}/metadata.json"
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [
            {
                "Name": "barch"
            }
        ],
        "Description": "Breeze Dark with pure black OLED backgrounds",
       "EnabledByDefault": true,
        "Id": "org.kde.breezedark-oled.desktop",
        "License": "LGPL-2.0-or-later",
        "Name": "Breeze Dark OLED",
        "Version": "1.0",
        "Website": "https://kde.org"
    },
    "X-Plasma-API": "5.0"
}
EOF
        cat <<EOF > "${LNF_DIR}/contents/defaults/kdeglobals"
[General]
ColorScheme=Breeze-Dark-OLED

[KDE]
widgetStyle=Breeze

[Icons]
Theme=${ICON_THEME:-breeze}
EOF
        cat <<'EOF' > "${LNF_DIR}/contents/defaults/plasmarc"
[Theme]
name=Breeze-Dark-OLED-Plasma
EOF
    fi

    # ─── Adwaita-AMOLED theme (GTK desktops, black only) ──────────────────────
    if [[ "$THEME" == "black" && "$DESKTOP" != "kde" ]]; then
        step "[8.3] Installing Adwaita-AMOLED theme"
        AMOLED_DIR="/usr/share/themes/Adwaita-AMOLED"
        mkdir -p "/mnt${AMOLED_DIR}"
        curl -fsSL "https://codeload.github.com/librerob/Adwaita-AMOLED/tar.gz/HEAD" \
            | tar -xz -C "/mnt${AMOLED_DIR}" --strip-components=1

        for HOME_DIR in "/mnt/etc/skel" "/mnt/home/${USER_NAME}"; do
            mkdir -p "$HOME_DIR/.config/gtk-4.0" \
                     "$HOME_DIR/.config/qt5ct/colors" \
                     "$HOME_DIR/.config/qt6ct/colors"
            cp "/mnt${AMOLED_DIR}/extra/libadwaita/gtk.css" \
               "/mnt${AMOLED_DIR}/extra/libadwaita/gtk-dark.css" \
               "/mnt${AMOLED_DIR}/extra/libadwaita/libadwaita-tweaks.css" \
               "$HOME_DIR/.config/gtk-4.0/"
            cp -r "/mnt${AMOLED_DIR}/extra/libadwaita/assets" \
               "$HOME_DIR/.config/gtk-4.0/"
            cp "/mnt${AMOLED_DIR}/extra/qt5ct/colors/Adwaita-AMOLED.conf" \
               "$HOME_DIR/.config/qt5ct/colors/"
            cp "/mnt${AMOLED_DIR}/extra/qt6ct/colors/Adwaita-AMOLED.conf" \
               "$HOME_DIR/.config/qt6ct/colors/"
        done
        arch-chroot /mnt chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.config"

        if [[ "$DESKTOP" != "lxqt" ]]; then
            printf '%s\n' "QT_QPA_PLATFORMTHEME=qt5ct" >> /mnt/etc/environment
        fi
    fi

    # ─── GTK theme name ───────────────────────────────────────────────────────
    GTK_THEME_NAME=""
    if [[ "$DARK_VARIANT" == true ]]; then
        GTK_THEME_NAME="Adwaita-dark"
        [[ "$THEME" == "black" ]] && GTK_THEME_NAME="Adwaita-AMOLED"
    fi

    # ─── dconf system defaults ────────────────────────────────────────────────
    DCONF_USED=false
    case "$DESKTOP" in
        gnome|cinnamon|mate)
            DCONF_USED=true
            arch-chroot /mnt pacman -S --noconfirm --needed dconf
            mkdir -p /mnt/etc/dconf/profile /mnt/etc/dconf/db/local.d
            cat <<'EOF' > /mnt/etc/dconf/profile/user
user-db:user
system-db:local
EOF
            ;;
    esac

    # ─── Desktop theme ────────────────────────────────────────────────────────
    step "[8.4] Applying theme to $DESKTOP"
    case "$DESKTOP" in
        # ─── XFCE ───────────────────────────────────────────────────────────
        xfce)
            XSETTINGS="/mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
            if [[ -f "$XSETTINGS" ]]; then
                [[ -n "$GTK_THEME_NAME" ]] && sed -i \
                    "s|\(name=\"ThemeName\" type=\"string\" value=\"\)[^\"]*|\1${GTK_THEME_NAME}|" \
                    "$XSETTINGS"
                [[ -n "$ICON_THEME" ]] && sed -i \
                    "s|\(name=\"IconThemeName\" type=\"string\" value=\"\)[^\"]*|\1${ICON_THEME}|" \
                    "$XSETTINGS"
            else
                mkdir -p "$(dirname "$XSETTINGS")"
                cat <<EOF > "$XSETTINGS"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="${GTK_THEME_NAME:-Adwaita}"/>
    <property name="IconThemeName" type="string" value="${ICON_THEME:-Adwaita}"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="MenuImages" type="bool" value="true"/>
    <property name="ButtonImages" type="bool" value="false"/>
    <property name="FontName" type="string" value="Sans 10"/>
    <property name="MonospaceFontName" type="string" value="Monospace 10"/>
  </property>
</channel>
EOF
            fi
            ;;
                # ─── KDE Plasma ─────────────────────────────────────────────────────
        kde)
            case "$THEME" in
                black)
                    KDE_COLORS="Breeze-Dark-OLED"              # /usr/share/color-schemes/Breeze-Dark-OLED.colors
                    KDE_PLASMA_THEME="Breeze-Dark-OLED-Plasma" # /usr/share/plasma/desktoptheme/Breeze-Dark-OLED-Plasma
                    KDE_LNF="org.kde.breezedark-oled.desktop"  # created in step 8.2
                    ;;
                dark)
                    KDE_COLORS="BreezeDark"                    # /usr/share/color-schemes/BreezeDark.colors
                    KDE_PLASMA_THEME="breeze-dark"             # /usr/share/plasma/desktoptheme/breeze-dark
                    KDE_LNF="org.kde.breezedark.desktop"       # shipped by the breeze package
                    ;;
                *)
                    KDE_COLORS=""
                    KDE_PLASMA_THEME=""
                    KDE_LNF="org.kde.breeze.desktop"
                    ;;
            esac

            [[ -d "/mnt/usr/share/plasma/look-and-feel/${KDE_LNF}" ]] || \
                echo -e "${YELLOW}[WARN]${NC} look-and-feel '${KDE_LNF}' not found"

            # On first login Plasma applies the look-and-feel package named by
            # LookAndFeelPackage; an invalid or missing name falls back to the
            # default light breeze package, overriding other system defaults.
            {
                echo "[KDE]"
                echo "LookAndFeelPackage=${KDE_LNF}"
                if [[ "$DARK_VARIANT" == true ]]; then
                    echo "widgetStyle=Breeze"
                    echo ""
                    echo "[General]"
                    echo "ColorScheme=${KDE_COLORS}"
                fi
                if [[ -n "$ICON_THEME" ]]; then
                    echo ""
                    echo "[Icons]"
                    echo "Theme=${ICON_THEME}"
                fi
            } > /mnt/etc/xdg/kdeglobals

            if [[ "$DARK_VARIANT" == true ]]; then
                # plasmarc: plasma shell theme (panels, widgets, popups)
                printf '[Theme]\nname=%s\n' "$KDE_PLASMA_THEME" > /mnt/etc/xdg/plasmarc

                # GTK apps under Plasma
                mkdir -p /mnt/etc/gtk-3.0
                cat <<EOF > /mnt/etc/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=${ICON_THEME:-breeze}
gtk-application-prefer-dark-theme=true
EOF
            fi

            # seed the user config too: guarantees the theme even if the
            # first-login look-and-feel application does not run
            for HOME_DIR in "/mnt/etc/skel" "/mnt/home/${USER_NAME}"; do
                mkdir -p "$HOME_DIR/.config"
                cp /mnt/etc/xdg/kdeglobals "$HOME_DIR/.config/kdeglobals"
                if [[ "$DARK_VARIANT" == true ]]; then
                    cp /mnt/etc/xdg/plasmarc "$HOME_DIR/.config/plasmarc"
                fi
            done
            arch-chroot /mnt chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.config"
            ;;
        # ─── GNOME ──────────────────────────────────────────────────────────
        gnome)
            {
                echo "[org/gnome/desktop/interface]"
                if [[ "$DARK_VARIANT" == true ]]; then
                    echo "color-scheme='prefer-dark'"
                    echo "gtk-theme='${GTK_THEME_NAME}'"
                fi
                [[ -n "$ICON_THEME" ]] && echo "icon-theme='${ICON_THEME}'"
            } > /mnt/etc/dconf/db/local.d/00-theme
            ;;
        # ─── Cinnamon ───────────────────────────────────────────────────────
        cinnamon)
            {
                echo "[org/cinnamon/desktop/interface]"
                [[ "$DARK_VARIANT" == true ]] && echo "gtk-theme='${GTK_THEME_NAME}'"
                [[ -n "$ICON_THEME" ]] && echo "icon-theme='${ICON_THEME}'"
                if [[ "$DARK_VARIANT" == true ]]; then
                    CINNAMON_SHELL_THEME="cinnamon"
                    [[ "$THEME" == "black" ]] && CINNAMON_SHELL_THEME="Adwaita-AMOLED"
                    echo ""
                    echo "[org/cinnamon/theme]"
                    echo "name='${CINNAMON_SHELL_THEME}'"
                fi
            } > /mnt/etc/dconf/db/local.d/00-theme
            ;;
        # ─── MATE ───────────────────────────────────────────────────────────
        mate)
            {
                echo "[org/mate/interface]"
                if [[ "$DARK_VARIANT" == true ]]; then
                    MATE_GTK_THEME="BlackMATE"
                    [[ "$THEME" == "black" ]] && MATE_GTK_THEME="Adwaita-AMOLED"
                    echo "gtk-theme='${MATE_GTK_THEME}'"
                fi
                [[ -n "$ICON_THEME" ]] && echo "icon-theme='${ICON_THEME}'"
                if [[ "$DARK_VARIANT" == true ]]; then
                    echo ""
                    echo "[org/mate/marco/general]"
                    echo "theme='${MATE_GTK_THEME}'"
                fi
            } > /mnt/etc/dconf/db/local.d/00-theme
            ;;
        # ─── LXQt ───────────────────────────────────────────────────────────
        lxqt)
            mkdir -p /mnt/etc/xdg/lxqt
            {
                echo "[General]"
                [[ "$DARK_VARIANT" == true ]] && echo "theme=dark"
                echo "icon_theme=${ICON_THEME:-breeze}"
            } > /mnt/etc/xdg/lxqt/lxqt.conf
            if [[ "$DARK_VARIANT" == true ]]; then
                mkdir -p /mnt/etc/gtk-3.0
                cat <<EOF > /mnt/etc/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=${GTK_THEME_NAME}
gtk-icon-theme-name=${ICON_THEME:-breeze}
gtk-application-prefer-dark-theme=true
EOF
            fi
            if [[ "$THEME" == "black" ]]; then
                mkdir -p /mnt/etc/xdg/openbox
                cat <<'EOF' > /mnt/etc/xdg/openbox/lxqt-rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Adwaita-AMOLED</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
</openbox_config>
EOF
            fi
            ;;
    esac

    [[ "$DCONF_USED" == true ]] && arch-chroot /mnt dconf update

    # ─── Display manager theme ────────────────────────────────────────────────
    if [[ "$DARK_VARIANT" == true && -n "$DE_DM" ]]; then
        step "[8.5] Applying theme to $DE_DM"
        case "$DE_DM" in
            lightdm)
                mkdir -p /mnt/etc/lightdm
                LIGHTDM_BG=""
                [[ "$THEME" == "black" ]] && \
                    LIGHTDM_BG=$'background=#000000\n'
                cat <<EOF > /mnt/etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
theme-name=${GTK_THEME_NAME}
icon-theme-name=${ICON_THEME:-Adwaita}
${LIGHTDM_BG}indicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power
EOF
                ;;
            sddm)
                SDDM_BACKGROUND="#232629"
                [[ "$THEME" == "black" ]] && SDDM_BACKGROUND="#000000"
                mkdir -p /mnt/etc/sddm.conf.d /mnt/usr/share/sddm/themes/breeze
                cat <<'EOF' > /mnt/etc/sddm.conf.d/20-theme.conf
[Theme]
Current=breeze
EOF
                cat <<EOF > /mnt/usr/share/sddm/themes/breeze/theme.conf.user
[General]
type=color
color=${SDDM_BACKGROUND}
background=
showClock=true
showlogo=false
EOF
                ;;
        esac
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [9.0] VM UTILS
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$VIRTUALBOX_GUEST_UTILS" == true || "$QEMU_GUEST_UTILS" == true ]]; then
    sect "9.0" "VM Utils"

    # ─── VirtualBox ───────────────────────────────────────────────────────────
    if [[ "$VIRTUALBOX_GUEST_UTILS" == true ]]; then
        step "[9.1] Installing VirtualBox Guest Utils"
        arch-chroot /mnt pacman -S --noconfirm virtualbox-guest-utils
        arch-chroot /mnt systemctl enable vboxservice.service
        arch-chroot /mnt usermod -aG vboxsf "${USER_NAME}"
    fi

    # ─── QEMU/KVM ─────────────────────────────────────────────────────────────
    if [[ "$QEMU_GUEST_UTILS" == true ]]; then
        step "[9.2] Installing QEMU/KVM Guest Utils"
        arch-chroot /mnt pacman -S --noconfirm qemu-guest-agent spice-vdagent
        arch-chroot /mnt systemctl enable qemu-guest-agent.service
        arch-chroot /mnt systemctl enable spice-vdagentd.service
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [10.0] AUR HELPER
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$AUR" == true ]]; then
    sect "10.0" "AUR Helper"

    # ─── yay ──────────────────────────────────────────────────────────────────
    step "[10.1] Installing yay"
    arch-chroot /mnt pacman -S --noconfirm --needed base-devel git
    arch-chroot /mnt sudo -u "${USER_NAME}" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "/home/${USER_NAME}/yay-bin"
    arch-chroot /mnt bash -c "cd /home/${USER_NAME}/yay-bin && sudo -u ${USER_NAME} makepkg"
    arch-chroot /mnt bash -c "pacman -U --noconfirm /home/${USER_NAME}/yay-bin/yay-bin-*.pkg.tar.zst"
    rm -rf "/mnt/home/${USER_NAME}/yay-bin"
fi

# ─── END ──────────────────────────────────────────────────────────────────────
ELAPSED=$SECONDS
if (( ELAPSED >= 3600 )); then
    printf -v ELAPSED_FMT '%dh %dm %ds' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60))
else
    printf -v ELAPSED_FMT '%dm %ds' $((ELAPSED/60)) $((ELAPSED%60))
fi
step "DONE (${ELAPSED_FMT})"