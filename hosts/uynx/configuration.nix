{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [
    # Generated on the target machine by `nixos-generate-config --root /mnt`.
    # Uncomment after first install (or copy the generated file in):
    # ./hardware-configuration.nix
  ];

  # --- Asahi / Apple Silicon (required) ---
  hardware.asahi.enable = true;

  boot.loader.systemd-boot.enable = true;
  # Asahi UEFI: must stay false (installer docs).
  boot.loader.efi.canTouchEfiVariables = false;

  # US keyboard: stop ` / < swap on Apple keyboards (common Asahi fix).
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
  '';

  networking.hostName = "uynx";
  networking.networkmanager.enable = true;
  # iwd: better WPA3 on Broadcom (Asahi docs recommendation).
  networking.networkmanager.wifi.backend = "iwd";

  time.timeZone = "America/Chicago";

  # Determinate Nix (module from determinate input). Keep flakes on.
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

  # Docker replaces Colima/Lima on Linux (native, not VM-in-VM).
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
    # Set password on install (`passwd`) or with hashedPassword later.
  };

  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
  ];

  # Dual-boot: console first; add DE/WM later (no AeroSpace on Linux).
  # services.xserver.enable = true;

  system.stateVersion = "25.11";
}
