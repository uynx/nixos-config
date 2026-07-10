{
  description = "NixOS on Apple Silicon (Asahi) — uynx";

  inputs = {
    # Unstable: nixos-apple-silicon tracks this closely for kernel/firmware.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-apple-silicon,
      home-manager,
      nix-index-database,
      ...
    }:
    {
      nixosConfigurations = {
        # M1 Pro MacBook Pro (MacBookPro18,3) — dual-boot or bare metal Asahi.
        # hardware-configuration.nix is generated on the machine during install.
        "uynx" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            nixos-apple-silicon.nixosModules.apple-silicon-support
            ./hosts/uynx/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "bak";
                extraSpecialArgs = { inherit inputs; };
                sharedModules = [
                  nix-index-database.homeModules.nix-index
                ];
                # users.uynx = import ./hosts/uynx/home.nix;  # add after install
              };
            }
          ];
        };
      };
    };
}
