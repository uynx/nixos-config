{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  hardware = {
    asahi = {
      enable = true;
      peripheralFirmwareDirectory = ../../firmware;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
    };
    extraModprobeConfig = ''
      options hid_apple iso_layout=0
    '';
  };

  networking = {
    hostName = "uynx";
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
  };

  time.timeZone = "America/Chicago";

  determinate.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  nix.settings = {
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "uynx"
    ];
    substituters = [
      "https://nix-community.cachix.org"
      "https://numtide.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWnL9yCkD69XfYIa2VclDuxsBeE266mGrW0o="
    ];
  };

  nixpkgs.config.allowUnfree = true;

  documentation = {
    enable = false;
    doc.enable = false;
    man.enable = false;
    info.enable = false;
  };

  virtualisation.docker.enable = true;

  users.users.uynx = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "docker"
    ];
    shell = pkgs.fish;
  };

  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    ghostty
    fuzzel
    brave
    antigravity
    brightnessctl
  ];

  services = {
    blueman.enable = true;
    xserver.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
          user = "greeter";
        };
      };
    };
    gnome.gnome-keyring.enable = true;
  };

  security.pam.services.greetd.enableGnomeKeyring = true;

  fonts.packages = with pkgs; [
    nerd-fonts.hack
    julia-mono
  ];

  programs.hyprland.enable = true;

  system.stateVersion = "25.11";
}
