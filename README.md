# barch

A basic Arch Linux installer in bash. Automates a complete installation from
the live ISO: GPT partitioning, LUKS encryption, LVM, ext4 or btrfs, GRUB,
and an optional desktop environment with theming.

## Usage

Boot the Arch live ISO, then:

    vim barch.sh   # edit the variables at the top
    bash barch.sh

## Variables

All configuration is done via the variables at the top of the script.

### System

| Variable | Default | Values | Description |
|---|---|---|---|
| `HOST_NAME` | `computer` | any valid hostname | System hostname. |
| `USER_NAME` | `user` | any valid username | User to create; added to the `wheel` group with sudo access. |
| `USER_PASS` | `changeme` | any string | Password of the user. |
| `ROOT_PASS` | `changeme` | any string | Password of root. |
| `TIMEZONE` | `Europe/Rome` | any path under `/usr/share/zoneinfo`, e.g. `America/New_York` | System timezone. |
| `LOCALE` | `en_GB.UTF-8` | any locale, e.g. `en_US.UTF-8`, `it_IT.UTF-8` | System locale. |
| `KEYBOARD` | `us` | any console keymap, e.g. `it`, `de` (see `localectl list-keymaps`) | Console keymap. |
| `MIRRORS` | `Sweden` | any country known to reflector (see `reflector --list-countries`) | Country used to select the fastest pacman mirrors. |

### Disk

| Variable | Default | Values | Description |
|---|---|---|---|
| `DISK` | `/dev/sda` | any block device, e.g. `/dev/sda`, `/dev/nvme0n1`, `/dev/mmcblk0` | Target disk. **Completely wiped**: GPT with a 1 GiB EFI partition and a LUKS-encrypted LVM root. |
| `FILESYSTEM` | `ext4` | `ext4`, `btrfs` | Root filesystem. With `btrfs`, subvolumes `@`, `@home`, `@pkg`, `@log`, `@swap` are created and mounted with `noatime,compress=zstd`. |
| `LUKS_PASS` | `changeme` | any string | Passphrase for LUKS disk encryption. |
| `SWAP` | `auto` | `auto`, size in MiB (e.g. `4096`), `false` | Swap configuration. `auto` sizes the swapfile from total RAM: 2× RAM up to 2 GB, 1× RAM up to 8 GB, ½ RAM up to 64 GB, 4 GB above that. Unless `false`, both zram (½ RAM, high priority) and the swapfile (low priority) are enabled. `false` disables all swap. |

### Desktop

| Variable | Default | Values | Description |
|---|---|---|---|
| `DESKTOP` | `xfce` | `xfce`, `kde`, `gnome`, `cinnamon`, `mate`, `lxqt`, `none` | Desktop environment to install. `none` = headless install, no GUI and no display manager. |
| `PACKAGES_REMOVE` | `(parole xfburn xfce4-screenshooter)` | space-separated package names, `()` = none | Packages removed after installation. Applied only with `DESKTOP=xfce`. |
| `PACKAGES_INSTALL` | `(mpv flameshot)` | space-separated package names, `()` = none | Extra packages installed after the desktop. Ignored with `DESKTOP=none`. |
| `DARK_THEME` | `true` | `true`, `false` | Apply a dark theme to the desktop and the display manager. |
| `EXTRA_THEMES` | `false` | `true`, `false` | Use the Adwaita-AMOLED theme instead of the stock dark themes. Requires `DARK_THEME=true`. |
| `BLUETOOTH` | `true` | `true`, `false` | Install and enable the Bluetooth stack (with blueman or bluedevil on desktop). |
| `PRINTING` | `true` | `true`, `false` | Install and enable CUPS printing. Ignored with `DESKTOP=none`. |
| `NIGHT_LIGHT` | `true` | `true`, `false` | Enable night light at the coordinates below. Native on KDE/GNOME/Cinnamon, redshift on XFCE/MATE/LXQt. Ignored with `DESKTOP=none`. |
| `NIGHT_LIGHT_LATITUDE` | `41.9` | decimal degrees, e.g. `45.46` | Latitude for night light. |
| `NIGHT_LIGHT_LONGITUDE` | `12.5` | decimal degrees, e.g. `9.19` | Longitude for night light. |

### Hardware and extras

| Variable | Default | Values | Description |
|---|---|---|---|
| `INSTALL_CPU_UCODE` | `true` | `true`, `false` | Install CPU microcode. Vendor (Intel/AMD) is auto-detected. |
| `INSTALL_GPU_DRIVERS` | `true` | `true`, `false` | Install GPU drivers. Vendor (Intel/AMD/NVIDIA/VM) is auto-detected. |
| `VIRTUALBOX_GUEST_UTILS` | `false` | `true`, `false` | Install VirtualBox guest utilities and enable `vboxservice`. |
| `OS_PROBER` | `false` | `true`, `false` | Detect other operating systems in GRUB (dual boot). |
| `AUR` | `true` | `true`, `false` | Install the yay AUR helper. |

## Warning

This script erases and repartitions the target disk. All data on `DISK` will
be permanently lost.

## License

GPL-3.0-or-later
