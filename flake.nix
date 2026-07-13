{
  description = "My Asahi NixOS configuration";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*";

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

    nixpkgs-stable.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-26.05-chilled/*";

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
      nixpkgs-stable,
      ...
    }:
    {
      nixosConfigurations = {
        "uynx" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./configuration.nix
            determinate.nixosModules.default
            nixos-apple-silicon.nixosModules.apple-silicon-support
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "bak";
                extraSpecialArgs = {
                  inherit inputs;
                  pkgs-stable = import nixpkgs-stable {
                    system = "aarch64-linux";
                    config.allowUnfree = true;
                  };
                };
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
