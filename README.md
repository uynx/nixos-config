# nixos-config

NixOS flake for Apple Silicon (Asahi) on **MacBookPro18,3** (M1 Pro). Separate from macOS `~/nix-darwin-config`.

## Inputs

| Input | Role |
|-------|------|
| `nixpkgs` (`nixos-unstable`) | Base packages / modules |
| `nixos-apple-silicon` | Asahi kernel, m1n1/U-Boot, firmware hooks |
| `home-manager` | User env (hooked; user module commented until install) |
| `nix-index-database` | `comma` / nix-index for HM |

## Status

Scaffold only. Next:

1. Build/download Asahi NixOS installer ISO ([uefi-standalone guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md))
2. Asahi installer → UEFI environment + free space
3. Install, generate `hosts/uynx/hardware-configuration.nix`, uncomment import
4. Port CLI/home pieces from Darwin `home.nix` carefully (not a drop-in)

## Rebuild (on NixOS)

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#uynx
```
