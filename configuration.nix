{ pkgs, ... }:
let
  muvm-fex-wrapper = pkgs.writeShellScriptBin "muvm-fex-wrapper" ''
    exec muvm -f /home/uynx/.local/share/fex-emu/RootFS/Ubuntu_24_04.ero -- "$@"
  '';
in
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
          JustWorksRepairing = "always";
        };
      };
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
    binfmt.registrations = {
      x86_64-linux = {
        recognitionType = "magic";
        magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
        mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
        interpreter = "${muvm-fex-wrapper}/bin/muvm-fex-wrapper";
      };
      i686-linux = {
        recognitionType = "magic";
        magicOrExtension = ''\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00'';
        mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
        interpreter = "${muvm-fex-wrapper}/bin/muvm-fex-wrapper";
      };
    };
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
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    ghostty
    fuzzel
    antigravity
    brightnessctl
    muvm
    muvm-fex-wrapper
  ];

  services = {
    blueman.enable = true;
    udev.extraRules = ''
      KERNEL=="kvm", GROUP="kvm", MODE="0660"
    '';
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

  security.pam.services.greetd.enableGnomeKeyring = true;
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    julia-mono
  ];
  console.useXkbConfig = true;
  system.stateVersion = "26.05";
}
