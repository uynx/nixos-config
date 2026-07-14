{
  config,
  pkgs,
  lib,
  pkgs-stable,
  ...
}:

let
  H = "${pkgs.hyprland}/bin/hyprctl";
  J = "${pkgs.jq}/bin/jq";
  workspace-switcher = pkgs.writeShellScriptBin "workspace-switcher" ''
    KEY=$1
    ACTION=''${2:-goto}
    STATE=/tmp/hyprland_merged_workspaces
    HDMI=$(grep -q "^connected$" /sys/class/drm/*-HDMI-A-1/status 2>/dev/null && echo 1 || echo 0)

    if [ "$ACTION" = sync ]; then
      if [ "$HDMI" = 0 ]; then
        if [ ! -f "$STATE" ]; then
          CUR=$(${H} activeworkspace -j | ${J} -r .id)
          : >"$STATE"
          ${H} clients -j | ${J} -r '.[]|select(.workspace.id>=4 and .workspace.id<=6)|"\(.workspace.id):\(.address)"' |
            while IFS=: read -r ws addr; do
              echo "$ws:$addr" >>"$STATE"
              ${H} dispatch movetoworkspacesilent "$((ws - 3)),address:$addr"
            done
          [ "$CUR" -ge 4 ] && [ "$CUR" -le 6 ] && ${H} dispatch workspace "$((CUR - 3))"
        fi
      else
        for ws in 1 2 3; do ${H} dispatch moveworkspacetomonitor "$ws HDMI-A-1"; done
        if [ -f "$STATE" ]; then
          while IFS=: read -r o a; do ${H} dispatch movetoworkspacesilent "$o,address:$a"; done <"$STATE"
          rm -f "$STATE"
        fi
      fi
      exit 0
    fi

    BASE=1
    if [ "$HDMI" = 1 ]; then
      [ "$(${H} monitors -j | ${J} -r '.[]|select(.focused==true)|.name')" != HDMI-A-1 ] && BASE=4
    fi
    case "$KEY" in
      u) T=$BASE ;; i) T=$((BASE + 1)) ;; o) T=$((BASE + 2)) ;; *) exit 1 ;;
    esac
    ${H} dispatch "$([ "$ACTION" = move ] && echo movetoworkspace || echo workspace)" "$T"
  '';

  monitor-hotplug = pkgs.writeShellScriptBin "monitor-hotplug" ''
    ${pkgs.systemd}/bin/udevadm monitor --subsystem=drm --udev | while read -r line; do
      echo "$line" | grep -q change || continue
      sleep 0.25
      ${workspace-switcher}/bin/workspace-switcher "" sync
    done
  '';

  peggle = pkgs.writeShellScriptBin "peggle" ''
    REG_FILE="/home/uynx/.local/share/steam-asahi/home/.local/share/Steam/steamapps/compatdata/3540/pfx/user.reg"
    RESOLUTION=$(${H} monitors -j | ${J} -r 'if any(.name == "HDMI-A-1") then .[] | select(.name == "HDMI-A-1") else .[] | select(.focused) end | "\(((.width / .scale) - .reserved[0] - .reserved[2] - 12) | floor)x\(((.height / .scale) - .reserved[1] - .reserved[3] - 12) | floor)"')
    if [ -f "$REG_FILE" ]; then
      sed -i -E "s/\"Default\"=\"[0-9]+x[0-9]+\"/\"Default\"=\"''$RESOLUTION\"/g" "$REG_FILE"
      sed -i -E "s/\"Peggle\"=\"[0-9]+x[0-9]+\"/\"Peggle\"=\"''$RESOLUTION\"/g" "$REG_FILE"
    fi
    exec ${pkgs.distrobox}/bin/distrobox enter steam-asahi -- \
      env FEX_X87REDUCEDPRECISION=1 \
      steam -silent -applaunch 3540
  '';

  steam = pkgs.writeShellScriptBin "steam" ''
    RESOLUTION=$(${H} monitors -j | ${J} -r 'if any(.name == "HDMI-A-1") then .[] | select(.name == "HDMI-A-1") else .[] | select(.focused) end | "\(((.width / .scale) - .reserved[0] - .reserved[2] - 12) | floor)x\(((.height / .scale) - .reserved[1] - .reserved[3] - 12) | floor)"')
    for reg in /home/uynx/.local/share/steam-asahi/home/.local/share/Steam/steamapps/compatdata/*/pfx/user.reg; do
      if [ -f "$reg" ]; then
        sed -i -E "s/\"Default\"=\"[0-9]+x[0-9]+\"/\"Default\"=\"''$RESOLUTION\"/g" "$reg"
        sed -i -E "s/\"Peggle\"=\"[0-9]+x[0-9]+\"/\"Peggle\"=\"''$RESOLUTION\"/g" "$reg"
      fi
    done
    exec ${pkgs.distrobox}/bin/distrobox enter steam-asahi -- steam "$@"
  '';

  update-brave-origin = pkgs.writers.writePython3Bin "update-brave-origin" { } ''
    import os
    import re
    import subprocess
    import urllib.request

    base = "https://brave-browser-apt-release.s3.brave.com"
    url = f"{base}/dists/stable/main/binary-arm64/Packages"
    idx = urllib.request.urlopen(url).read().decode()
    pat = r"Package: brave-origin\n.*?Version: ([\d.]+)"
    latest = re.search(pat, idx, re.DOTALL).group(1)
    path = os.path.expanduser("~/nixos-config/hosts/uynx/brave-origin.nix")
    text = open(path).read()
    cur = re.search(r'version = "([\d.]+)";', text).group(1)
    print(f"Current: {cur} | Latest: {latest}")
    if cur == latest:
        print("Already up to date.")
        raise SystemExit(0)


    def h(arch):
        url = (
            f"{base}/pool/main/b/brave-origin/"
            f"brave-origin_{latest}_{arch}.deb"
        )
        print(f"Hashing {arch}...")
        cmd = ["nix-prefetch-url", url]
        pf = subprocess.run(
            cmd, capture_output=True, text=True, check=True
        )
        cmd_convert = [
            "nix", "hash", "convert",
            "--hash-algo", "sha256",
            "--to", "sri",
            pf.stdout.strip()
        ]
        return subprocess.run(
            cmd_convert, capture_output=True, text=True, check=True
        ).stdout.strip()


    arm, amd = h("arm64"), h("amd64")
    text = re.sub(r'version = "[^"]+";', f'version = "{latest}";', text)
    text = re.sub(
        r'hash = if arch == "arm64" then "[^"]+"\s+else "[^"]+";',
        f'hash = if arch == "arm64" then "{arm}"\n         else "{amd}";',
        text,
    )
    open(path, "w").write(text)
    print("Updated brave-origin.nix successfully!")
  '';

  home = "/home/uynx";
in
{
  home = {
    username = "uynx";
    homeDirectory = home;
    stateVersion = "26.05";
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      AGY_CLI_DISABLE_AUTO_UPDATE = "true";
      PROTON_PASS_KEY_PROVIDER = "fs";
    };
    pointerCursor = {
      enable = true;
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors";
      size = 24;
    };
    packages = with pkgs; [
      hyprlandPlugins.hy3
      hyprpaper
      coreutils
      wget
      dust
      duf
      procs
      sd
      gping
      doggo
      obsidian
      tokei
      hyperfine
      bandwhich
      (neovim.override {
        withNodeJs = true;
        withPython3 = true;
      })
      tree-sitter
      nodejs
      rustc
      (python3.withPackages (
        ps: with ps; [
          pip
          setuptools
        ]
      ))
      gnumake
      lua5_1
      luarocks
      julia-bin
      php
      php.packages.composer
      ruby
      uv
      imagemagick
      ghostscript
      mermaid-cli
      nil
      nixfmt
      statix
      (pkgs-stable.texlive.withPackages (
        ps: with ps; [
          scheme-full
          biber
        ]
      ))
      proton-vpn
      proton-pass-cli
      qbittorrent
      wireshark
      dive
      distrobox
      swi-prolog
      libreoffice
      cava
      socat
      tmux
      tmuxPlugins.sensible
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.resurrect
      tmuxPlugins.continuum
      monitor-hotplug
      peggle
      steam
      workspace-switcher
      update-brave-origin
      obs-studio
    ];
    file = {
      ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/nvim";
      ".local/share/nvim/site/parser/norg.so".source =
        "${pkgs.tree-sitter-grammars.tree-sitter-norg}/parser";
      ".config/ghostty/config".text = ''
        config-file = ${home}/dotfiles/ghostty_config
        font-size = 12
      '';
      ".config/hypr/hyprland.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/hypr/hyprland.conf";
      ".config/hypr/hyprpaper.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/hypr/hyprpaper.conf";
      ".config/fuzzel/fuzzel.ini".source =
        config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/fuzzel/fuzzel.ini";
      ".config/waybar".source = config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/waybar";
      ".config/tmux".source = config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/tmux";
      ".agents/skills".source = config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/skills";
      ".agents/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${home}/dotfiles/AGENTS.md";
      ".config/cava/config".text = ''
        [general]
        bars = 16
        framerate = 60
        [input]
        method = pipewire
        source = auto
        [output]
        method = raw
        raw_target = /dev/stdout
        data_format = ascii
        ascii_max_range = 7
      '';
    };
    activation.copilotBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      AUTH_DB="${home}/.config/github-copilot/auth.db"
      HOSTS_JSON="${home}/.config/github-copilot/hosts.json"
      if [ -f "$AUTH_DB" ]; then
        TOKEN=$(${pkgs.sqlite}/bin/sqlite3 "$AUTH_DB" "SELECT cast(token_ciphertext as text) FROM oauth_tokens LIMIT 1;" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
          mkdir -p "$(dirname "$HOSTS_JSON")"
          printf '{\n  "github.com": {\n    "oauth_token": "%s"\n  }\n}\n' "$TOKEN" >"$HOSTS_JSON"
          chmod 600 "$HOSTS_JSON"
        fi
      fi
    '';
    activation.createRequiredDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p \
        "${home}/ai_memory/concepts" \
        "${home}/ai_memory/journal" \
        "${home}/dotfiles" \
        "${home}/nixos-config"
    '';
  };

  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  xdg.desktopEntries = {
    peggle = {
      name = "Peggle";
      genericName = "Game";
      exec = "peggle";
      icon = "steam";
      terminal = false;
      categories = [ "Game" ];
    };
    steam = {
      name = "Steam";
      genericName = "Games Store";
      exec = "steam";
      icon = "steam";
      terminal = false;
      categories = [ "Network" "FileTransfer" "Game" ];
    };
  };

  programs = {
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        editor = "nvim";
      };
    };
    ghostty.enable = true;
    waybar.enable = true;
    fastfetch.enable = true;
    bun.enable = true;
    lazydocker.enable = true;
    java.enable = true;
    cargo.enable = true;
    vscodium.enable = true;
    man = {
      enable = true;
      generateCaches = true;
    };
    zoxide.enable = true;
    yazi = {
      enable = true;
      shellWrapperName = "y";
      settings.manager = {
        show_hidden = true;
        sort_by = "modified";
        sort_dir_first = true;
      };
    };
    bat.enable = true;
    eza = {
      enable = true;
      icons = "auto";
      git = true;
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };
    btop.enable = true;
    fd = {
      enable = true;
      hidden = true;
    };
    tealdeer = {
      enable = true;
      settings.updates.auto_update = true;
    };
    atuin.enable = true;
    fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting ""
        fish_vi_key_bindings
      '';
      functions.reb.body = ''
        set -l target "uynx"
        if test (count $argv) -gt 0; set target $argv[1]; end
        sudo nixos-rebuild switch --flake ~/nixos-config#$target --impure
      '';
      functions.pass-find.body = ''
        if not pass-cli test >/dev/null 2>&1
            pass-cli test
            or return 1
        end
        pass-cli item list Personal --output json | jq -r '(.items // .)[] | "[\((.item_type // .itemType // .type // "unknown") | ascii_upcase)] \(.title // .name)\t\(.id // .item_id // .itemId)"' | fzf --ansi --header="Select an item to view credentials" --with-nth=1 | string split \t | read -l display_name id
        if test -n "$id"
            pass-cli item view --vault-name Personal --item-id $id
        end
      '';
      shellAliases = {
        update = "update-brave-origin && nix flake update --flake ~/nixos-config";
        word = "libreoffice --writer";
        powerpoint = "libreoffice --impress";
        gen = "nix-env --list-generations";
        wt = "git worktree list";
        wta = "git worktree add";
        wtr = "git worktree remove";
        vi = "nvim";
        vim = "nvim";
        tree = "eza --tree --icons";
        ll = "eza -la --icons --group-directories-first --header --git-ignore";
        pf = "pass-find";
      };
      plugins = [
        {
          name = "sudope";
          src = pkgs.fishPlugins.plugin-sudope;
        }
      ];
    };
    starship = {
      enable = true;
      settings = {
        add_newline = false;
        command_timeout = 3000;
      };
    };
    fzf = {
      enable = true;
      changeDirWidget.command = "fd --type d --hidden --strip-cwd-prefix --exclude .git";
      historyWidget.command = "";
    };
    ripgrep = {
      enable = true;
      arguments = [
        "--max-columns=150"
        "--max-columns-preview"
        "--hidden"
        "--glob=!.git/*"
        "--smart-case"
      ];
    };
    lazygit = {
      enable = true;
      settings = {
        gui.showIcons = true;
        git.paging = {
          colorArg = "always";
          pager = "bat --style=plain";
        };
      };
    };
    chromium = {
      enable = true;
      package = pkgs.callPackage ./brave-origin.nix { };
    };
    jq.enable = true;
    go.enable = true;
    sioyek.enable = true;
    nix-index.enable = true;
    nix-index-database.comma.enable = true;
    direnv = {
      enable = true;
      package = pkgs.direnv.overrideAttrs (_: {
        doCheck = false;
      });
      nix-direnv.enable = true;
    };
    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        theme = "Nord";
      };
    };
    git = {
      enable = true;
      settings = {
        user = {
          name = "Brandon Alexander";
          email = "brandonwalex@pm.me";
          signingkey = "~/.ssh/id_ed25519.pub";
        };
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        core = {
          editor = "nvim";
          fsmonitor = true;
          untrackedCache = true;
        };
        gpg.format = "ssh";
        commit.gpgsign = true;
        tag.gpgsign = true;
        merge.conflictstyle = "zdiff3";
        rerere.enabled = true;
      };
    };
  };
}
