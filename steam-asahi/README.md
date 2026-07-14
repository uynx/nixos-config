# Steam on NixOS Asahi

This keeps NixOS as the native 16 KiB-page ARM host. Fedora's Asahi packages
own the 4 KiB muvm guest, FEX, its Fedora root filesystem, virglrenderer, and
the Steam launcher. Do not add host-wide x86 binfmt handlers or manually patch
a FEX root filesystem.

The manifest uses Distrobox's separate `/dev` mode to avoid a Docker 29 devpts
mount conflict. Docker's privileged device setup still exposes KVM and the
Asahi render node to this trusted container.

## Install

Apply the NixOS configuration first:

```bash
reb
```

Log out and back in if `id -nG` does not contain `kvm` and `docker`. Then build
and create the container:

```bash
cd ~/nixos-config
docker build --tag localhost/steam-asahi:44 --file steam-asahi/Containerfile steam-asahi
distrobox assemble create --file steam-asahi/distrobox.ini
```

## Validate

Keep failures isolated by checking each layer in order:

```bash
getconf PAGESIZE
test -r /dev/kvm && test -w /dev/kvm

distrobox enter steam-asahi -- rpm -q muvm fex-emu fex-emu-rootfs-fedora \
  virglrenderer mesa-dri-drivers mesa-vulkan-drivers steam \
  xorg-x11-server-Xwayland
distrobox enter steam-asahi -- test -e /usr/lib64/dri/asahi_dri.so
distrobox enter steam-asahi -- test -e /usr/lib64/libvulkan_asahi.so
distrobox enter steam-asahi -- muvm -i -- FEXBash -c 'uname -m'
distrobox enter steam-asahi -- steam
```

The host page size should remain `16384`; the FEX command should print
`x86_64`. Only test Steam after those checks pass. Start with a lightweight
OpenGL title before testing Proton or demanding Vulkan games.

Peggle Nights has a dedicated launcher for Fedora Asahi's reduced-precision
x87 mode, which speeds up legacy game code:

```bash
peggle
```

Run it while Steam is fully stopped so the Steam process inherits the setting.

### Proton VPN

Steam does not need an inbound Proton VPN forwarded port for login or client
updates. On this host, large updater downloads repeatedly failed through the
Proton WireGuard route plus permanent kill switch, while DNS, HTTPS, and Steam
connection-manager tests still passed. Disconnect Proton VPN, restart the
container to create a fresh `passt` process, and relaunch Steam for updates:

```bash
docker restart steam-asahi
rm -rf "$XDG_RUNTIME_DIR/krun" "$XDG_RUNTIME_DIR/muvm.lock"
distrobox enter steam-asahi -- steam
```

Steam can be tested with the VPN again after the client update is complete. If
the route changes while Steam is running, fully exit and relaunch Steam.

## Update

The image follows Fedora 44 updates and the Asahi COPRs. Rebuild it, then
replace only this Distrobox:

```bash
cd ~/nixos-config
docker build --pull --tag localhost/steam-asahi:44 --file steam-asahi/Containerfile steam-asahi
distrobox assemble create --replace --file steam-asahi/distrobox.ini
```

The separate container home preserves Steam data across container replacement.
