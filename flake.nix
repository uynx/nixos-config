{
  description = "NixOS on Apple Silicon (Asahi) — uynx";

  inputs = {
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

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-apple-silicon,
      home-manager,
      nix-index-database,
      determinate,
      ...
    }:
    {
      nixosConfigurations = {
        "uynx" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            determinate.nixosModules.default
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
                users.uynx = import ./hosts/uynx/home.nix;
              };
            }
          ];
        };
      };
    };
}
