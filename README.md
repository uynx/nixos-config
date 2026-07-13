# nixos-config

NixOS flake for Apple Silicon (Asahi) on **MacBookPro18,3** (M1 Pro, ~1 TB SSD).  
Separate from macOS `~/nix-darwin-config`. Dual-boot target: **~½ disk each**.

## Inputs

| Input | Role |
|-------|------|
| `nixpkgs` (`nixos-unstable`) | Base packages / modules |
| `nixos-apple-silicon` | Asahi kernel, m1n1/U-Boot, firmware |
| `home-manager` | User env (`hosts/uynx/home.nix`) |
| `nix-index-database` | `comma` / nix-index |
| `determinate` | Determinate Nix (`nixosModules.default`) |

## Dual-boot size (this machine)

| | |
|--|--|
| Internal SSD | ~**994 GB** usable (APPLE SSD AP1024R) |
| macOS free today | ~**832 GB** free — resize is fine |
| Target | macOS ≈ **500 GB**, NixOS root ≈ **480–500 GB** (plus small EFI + stub from Asahi installer) |

Asahi installer does the **safe** resize of the APFS container. Do **not** use a generic partitioner on the whole disk (can brick recovery/iBoot).

## Home port vs Darwin

**Kept (Linux-ok):** CLI tools, nvim/tmux/ghostty/dotfiles + agents symlinks, fish/starship/atuin/…, git/gh, vscodium, discord, brave-origin (custom deb-packaged release), languages, texlive full, games/tools that are cross-platform.

**Dropped (mac-only):** AeroSpace, SketchyBar, duti, Colima, Lima, `whatsapp-for-mac`, Homebrew paths, quarantine `unb`, Darwin `targets.*`.

**Linux swaps:** Docker (system) instead of Colima; `pkgs.ghostty`; LibreOffice CLI aliases; `reb` → `nixos-rebuild`; home under `/home/uynx`; `brave` → custom deb-wrapped `brave-origin`.

## Custom Configurations

- **Brave Origin**: Managed via custom derivation in `./hosts/uynx/brave-origin.nix`. Fetches official Debian binary release, patches dynamically linked libraries (including `libxcb`), and wraps binary with `wrapGAppsHook3` to run natively on Wayland.
- **File Structure**: `configuration.nix` and `hardware-configuration.nix` are placed in the repository root.

## Rebuild (on NixOS)

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#uynx
```

Or use the `reb` alias:
```bash
reb
```

First rebuild with Determinate may need cache flags (see Determinate docs) if packages aren't cached yet.
