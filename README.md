# nixos-config (Asahi)

| Path | Role |
|------|------|
| `configuration.nix` | System (boot, hardware, services) |
| `hardware-configuration.nix` | Generated Asahi hardware |
| `flake.nix` | Inputs + `nixosConfigurations.uynx` |
| `hosts/uynx/home.nix` | Home Manager |
| `hosts/uynx/brave-origin.nix` | Brave Origin package |

```bash
reb              # rebuild
update && reb    # flake update + rebuild
```
