#!/bin/bash
# name: barch
# description: a basic arch installer in bash
# author: passthesh3ll
# license: GPL3

# ─── Helpers ──────────────────────────────────────────────────────────────────
set -euo pipefail
trap 'echo -e "\e[31m[ERROR]\e[0m line $LINENO: $BASH_COMMAND" >&2' ERR
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'
SECONDS=0
step() { echo -e "${YELLOW}=> $*${NC}"; }
sect() { echo -e "\n${GREEN}═══════ [$*] ═══════${NC}"; }

# ─── Installation Variables ───────────────────────────────────────────────────
HOST_NAME="computer"
USER_NAME="user"
USER_PASS="changeme"
ROOT_PASS="changeme"
DISK="/dev/sda"
FILESYSTEM="ext4"
LUKS_PASS="changeme"
SWAP="auto"
TIMEZONE="Europe/Rome"
LOCALE="en_GB.UTF-8"
KEYBOARD="us"
MIRRORS="Sweden"
DESKTOP="xfce"
PACKAGES_REMOVE=(parole xfburn xfce4-screenshooter)
PACKAGES_INSTALL=(mpv flameshot)
DARK_THEME=true
EXTRA_THEMES=false
BLUETOOTH=true
PRINTING=true
NIGHT_LIGHT=true
NIGHT_LIGHT_LATITUDE="41.9"
NIGHT_LIGHT_LONGITUDE="12.5"
INSTALL_CPU_UCODE=true
INSTALL_GPU_DRIVERS=true
VIRTUALBOX_GUEST_UTILS=false
OS_PROBER=false
AUR=true

# ═══════════════════════════════════════════════════════════════════════════════
# S T A R T
# ═══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${GREEN}        ╭─────────╮       ${NC}"
echo -e "${GREEN}        │  BARCH  │       ${NC}"
echo -e "${GREEN}        ╰─────────╯       ${NC}"
echo -e "${GREEN}       a basic arch       ${NC}"
echo -e "${GREEN}     installer in bash    ${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# [0.0] HARDWARE DETECTION
# ═══════════════════════════════════════════════════════════════════════════════
sect "0.0" "Detecting Hardware"

# ─── CPU microcode ────────────────────────────────────────────────────────────
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
        echo -e "\e[33m[WARN]\e[0m DESKTOP=$DESKTOP but GPU drivers disabled: the GUI may not work"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [1.0] DISK PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
sect "1.0" "Formatting Disk"

# ─── Filesystem check ─────────────────────────────────────────────────────────
case "$FILESYSTEM" in
    ext4|btrfs) ;;
    *)
        echo -e "\e[31m[ERROR]\e[0m Unknown FILESYSTEM: '$FILESYSTEM'" >&2
        exit 1
        ;;
esac

# ─── Swap check ───────────────────────────────────────────────────────────────
if [[ "$SWAP" != "auto" && "$SWAP" != "false" && ! "$SWAP" =~ ^[0-9]+$ ]]; then
    echo -e "\e[31m[ERROR]\e[0m Invalid SWAP: '$SWAP' (use auto, false or size in MiB)" >&2
    exit 1
fi

# ─── System clock ─────────────────────────────────────────────────────────────
step "[1.1] Syncing system clock"
timedatectl set-ntp true

# ─── Disk partitioning ────────────────────────────────────────────────────────
step "[1.2] Partitioning $DISK"
if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
    PART_BOOT="${DISK}p1"; PART_LUKS="${DISK}p2"
else
    PART_BOOT="${DISK}1";  PART_LUKS="${DISK}2"
fi
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 1025MiB 100%

# ─── LUKS encryption ──────────────────────────────────────────────────────────
step "[1.3] Setting up LUKS encryption"
printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --batch-mode "$PART_LUKS"
printf '%s' "$LUKS_PASS" | cryptsetup open --key-file - "$PART_LUKS" cryptlvm

# ─── LVM setup ────────────────────────────────────────────────────────────────
step "[1.4] Setting up LVM"
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm
lvcreate -l 100%FREE -n root vg0

# ─── Filesystems ──────────────────────────────────────────────────────────────
step "[1.5] Formatting filesystems"
mkfs.fat -F32 "$PART_BOOT"
case "$FILESYSTEM" in
    ext4)  mkfs.ext4 -F /dev/vg0/root ;;
    btrfs) mkfs.btrfs -f /dev/vg0/root ;;
esac

# ─── Mounting ─────────────────────────────────────────────────────────────────
step "[1.6] Mounting filesystems"
case "$FILESYSTEM" in
    ext4)
        mount /dev/vg0/root /mnt
        ;;
    btrfs)
        mount /dev/vg0/root /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@pkg
        btrfs subvolume create /mnt/@log
        btrfs subvolume create /mnt/@swap
        umount /mnt
        BTRFS_OPTS="noatime,compress=zstd"
        mount -o "${BTRFS_OPTS},subvol=@" /dev/vg0/root /mnt
        mkdir -p /mnt/home /mnt/var/cache/pacman/pkg /mnt/var/log /mnt/swap
        mount -o "${BTRFS_OPTS},subvol=@home" /dev/vg0/root /mnt/home
        mount -o "${BTRFS_OPTS},subvol=@pkg"  /dev/vg0/root /mnt/var/cache/pacman/pkg
        mount -o "${BTRFS_OPTS},subvol=@log"  /dev/vg0/root /mnt/var/log
        mount -o "noatime,subvol=@swap"       /dev/vg0/root /mnt/swap
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
reflector -c "$MIRRORS" -a 6 --sort rate --save /etc/pacman.d/mirrorlist

# ─── Base system ──────────────────────────────────────────────────────────────
step "[2.2] Installing base system"
FS_PACKAGES=()
[[ "$FILESYSTEM" == btrfs ]] && FS_PACKAGES=(btrfs-progs)
SWAP_PACKAGES=()
[[ "$SWAP" != false ]] && SWAP_PACKAGES=(zram-generator)
pacstrap -K /mnt \
    base base-devel linux linux-headers linux-firmware dkms \
    lvm2 grub efibootmgr networkmanager pacman-contrib nano git vim sudo \
    "${UCODE_PACKAGES[@]}" "${FS_PACKAGES[@]}" "${SWAP_PACKAGES[@]}" cronie lm_sensors

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
arch-chroot /mnt sed -i \
    's/^HOOKS=(.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' \
    /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# ═══════════════════════════════════════════════════════════════════════════════
# [4.0] BOOTLOADER
# ═══════════════════════════════════════════════════════════════════════════════
sect "4.0" "Configuring Bootloader"

# ─── GRUB ─────────────────────────────────────────────────────────────────────
step "[4.1] Configuring GRUB"
LUKS_UUID=$(blkid -s UUID -o value "$PART_LUKS")
KERNEL_PARAMS="loglevel=3 quiet cryptdevice=UUID=${LUKS_UUID}:cryptlvm:allow-discards root=/dev/vg0/root"
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
            plasma-nm plasma-pa kscreen powerdevil
            dolphin konsole kate ark gwenview okular spectacle
            sddm sddm-kcm layer-shell-qt
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
        echo -e "\e[31m[ERROR]\e[0m Unknown DESKTOP: '$DESKTOP'" >&2
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
# [7.0] THEMING
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$DESKTOP" != "none" && "$DARK_THEME" == true ]]; then
    sect "7.0" "Applying Themes"

    # ─── Papirus icons ────────────────────────────────────────────────────────
    step "[7.1] Installing Papirus icon theme"
    arch-chroot /mnt pacman -S --noconfirm papirus-icon-theme gnome-themes-extra gtk-engine-murrine
    ICON_THEME="Papirus-Dark"

    # ─── Adwaita AMOLED theme ─────────────────────────────────────────────────
    if [[ "$EXTRA_THEMES" == true ]]; then
        step "[7.2] Installing Adwaita-AMOLED theme"
        AMOLED_DIR="/usr/share/themes/Adwaita-AMOLED"
        git clone --depth 1 https://github.com/librerob/Adwaita-AMOLED "/mnt${AMOLED_DIR}"
        rm -rf "/mnt${AMOLED_DIR}/.git"

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

        GTK_THEME_NAME="Adwaita-AMOLED"
    else
        GTK_THEME_NAME="Adwaita-dark"
    fi

    # ─── dconf system defaults ────────────────────────────────────────────────
    DCONF_USED=false
    case "$DESKTOP" in
        kde|gnome|cinnamon|mate)
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
    step "[7.3] Applying dark theme"
    case "$DESKTOP" in
        # ─── XFCE ───────────────────────────────────────────────────────────
        xfce)
            mkdir -p /mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
            cat <<EOF > /mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="${GTK_THEME_NAME}"/>
    <property name="IconThemeName" type="string" value="${ICON_THEME}"/>
  </property>
</channel>
EOF
            cat <<'EOF' > /mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
  </property>
</channel>
EOF
            ;;
        # ─── KDE Plasma ─────────────────────────────────────────────────────
        kde)
            cat <<EOF > /mnt/etc/xdg/kdeglobals
[General]
ColorScheme=BreezeDark

[Icons]
Theme=${ICON_THEME}
EOF
            mkdir -p /mnt/etc/gtk-3.0
            cat <<EOF > /mnt/etc/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=${GTK_THEME_NAME}
gtk-icon-theme-name=${ICON_THEME}
gtk-application-prefer-dark-theme=true
EOF
            cat <<EOF > /mnt/etc/dconf/db/local.d/00-dark-theme
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='${GTK_THEME_NAME}'
icon-theme='${ICON_THEME}'
EOF
            ;;
        # ─── GNOME ──────────────────────────────────────────────────────────
        gnome)
            cat <<EOF > /mnt/etc/dconf/db/local.d/00-dark-theme
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='${GTK_THEME_NAME}'
icon-theme='${ICON_THEME}'
EOF
            ;;
        # ─── Cinnamon ───────────────────────────────────────────────────────
        cinnamon)
            CINNAMON_SHELL_THEME="cinnamon"
            [[ "$EXTRA_THEMES" == true ]] && CINNAMON_SHELL_THEME="Adwaita-AMOLED"
            cat <<EOF > /mnt/etc/dconf/db/local.d/00-dark-theme
[org/cinnamon/desktop/interface]
gtk-theme='${GTK_THEME_NAME}'
icon-theme='${ICON_THEME}'

[org/cinnamon/theme]
name='${CINNAMON_SHELL_THEME}'
EOF
            ;;
        # ─── MATE ───────────────────────────────────────────────────────────
        mate)
            MATE_GTK_THEME="${GTK_THEME_NAME}"
            MATE_WM_THEME="Adwaita-AMOLED"
            if [[ "$EXTRA_THEMES" != true ]]; then
                MATE_GTK_THEME="BlackMATE"
                MATE_WM_THEME="BlackMATE"
            fi
            cat <<EOF > /mnt/etc/dconf/db/local.d/00-dark-theme
[org/mate/interface]
gtk-theme='${MATE_GTK_THEME}'
icon-theme='${ICON_THEME}'

[org/mate/marco/general]
theme='${MATE_WM_THEME}'
EOF
            ;;
        # ─── LXQt ───────────────────────────────────────────────────────────
        lxqt)
            mkdir -p /mnt/etc/xdg/lxqt /mnt/etc/gtk-3.0
            cat <<EOF > /mnt/etc/xdg/lxqt/lxqt.conf
[General]
theme=dark
icon_theme=${ICON_THEME}
EOF
            cat <<EOF > /mnt/etc/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=${GTK_THEME_NAME}
gtk-icon-theme-name=${ICON_THEME}
gtk-application-prefer-dark-theme=true
EOF
            if [[ "$EXTRA_THEMES" == true ]]; then
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
    step "[7.4] Applying theme to $DE_DM"
    case "$DE_DM" in
        lightdm)
            mkdir -p /mnt/etc/lightdm
            LIGHTDM_BG=""
            [[ "$EXTRA_THEMES" == true ]] && \
                LIGHTDM_BG=$'background=#000000\n'
            cat <<EOF > /mnt/etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
theme-name=${GTK_THEME_NAME}
icon-theme-name=${ICON_THEME}
${LIGHTDM_BG}indicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power
EOF
            ;;
        sddm)
            if [[ "$EXTRA_THEMES" == true ]]; then
                mkdir -p "/mnt/usr/share/sddm/themes/breeze"
                cat <<EOF > /mnt/usr/share/sddm/themes/breeze/theme.conf.user
[General]
background=/usr/share/themes/Adwaita-AMOLED/extra/wallpaper/blackmount.png
type=image
EOF
            fi
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [8.0] VIRTUALBOX GUEST UTILS
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$VIRTUALBOX_GUEST_UTILS" == true ]]; then
    sect "8.0" "VirtualBox Guest Utils"

    # ─── Guest utils ──────────────────────────────────────────────────────────
    step "[8.1] Installing VirtualBox Guest Utils"
    arch-chroot /mnt pacman -S --noconfirm virtualbox-guest-utils
    arch-chroot /mnt systemctl enable vboxservice.service
    arch-chroot /mnt usermod -aG vboxsf "${USER_NAME}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# [9.0] AUR HELPER
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$AUR" == true ]]; then
    sect "9.0" "AUR Helper"

    # ─── yay ──────────────────────────────────────────────────────────────────
    step "[9.1] Installing yay"
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