{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  hardware = {
    asahi = {
      enable = true;
      peripheralFirmwareDirectory = /boot/vendorfw;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          AutoEnable = true;
        };
      };
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
    };
    kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.shrinker_enabled=1"
    ];
    extraModprobeConfig = ''
      options hid_apple iso_layout=0
      options uvcvideo quirks=0x80
    '';
  };

  networking = {
    hostName = "MacBook-Pro";
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
  };

  time.timeZone = "America/Chicago";
  determinate.enable = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings = {
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
  };

  nixpkgs.config.allowUnfree = true;
  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];
  virtualisation.docker.enable = true;

  users.users.uynx = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "docker"
      "kvm"
    ];
    shell = pkgs.fish;
  };

  programs = {
    fish.enable = true;
    hyprland.enable = true;
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        glib
        gtk3
        pango
        cairo
        atk
        at-spi2-core
        nspr
        nss
        libX11
        libXcomposite
        libXdamage
        libXext
        libXfixes
        libXrandr
        libxcb
        libxkbcommon
        mesa
        libgbm
        libglvnd
        expat
        dbus
        cups
        alsa-lib
        systemd
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    ghostty
    fuzzel
    brightnessctl
  ];

  services = {
    blueman.enable = true;
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        options = "caps:escape";
      };
    };
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
    greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
        user = "greeter";
      };
    };
    gnome.gnome-keyring.enable = true;
  };

  virtualisation.waydroid.enable = true;
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
  security.pam.services.greetd.enableGnomeKeyring = true;
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.hack
      julia-mono
      cantarell-fonts
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };
  console.useXkbConfig = true;
  system.stateVersion = "26.05";
}
