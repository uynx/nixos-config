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

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "uynx"
    ];
    # Optional later: Asahi community binary cache for kernels
    # https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/binary-cache.md
  };

  nixpkgs.config.allowUnfree = true;

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
