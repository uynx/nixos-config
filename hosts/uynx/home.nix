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

  steam-asahi-doctor = pkgs.writeShellScriptBin "steam-asahi-doctor" ''
    set -eu

    IMAGE=localhost/steam-asahi:44
    CONTAINER=steam-asahi

    [ "$(${pkgs.glibc.bin}/bin/getconf PAGESIZE)" = 16384 ]
    [ -r /dev/kvm ] && [ -w /dev/kvm ]
    ${pkgs.docker}/bin/docker image inspect "$IMAGE" >/dev/null
    ${pkgs.docker}/bin/docker container inspect "$CONTAINER" >/dev/null
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- rpm -q \
      asahi-platform-metapackage-fex-0-29.fc44.aarch64 \
      muvm-0.6.0-3.fc44.aarch64 \
      fex-emu-2604-1.fc44.aarch64 \
      'fex-emu-rootfs-fedora-44^20260410.n.0-1.fc44.noarch' \
      virglrenderer-1.3.0-1.fc44.aarch64 \
      mesa-dri-drivers-26.1.4-1.fc44.aarch64 \
      mesa-vulkan-drivers-26.1.4-1.fc44.aarch64 \
      steam-0-14.fc44.noarch \
      pulseaudio-utils-17.0-9.fc44.aarch64 \
      xorg-x11-server-Xwayland-24.1.13-1.fc44.aarch64 >/dev/null
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -e /usr/lib64/dri/asahi_dri.so
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -e /usr/lib64/libvulkan_asahi.so
    printf '%s\n' "Steam Asahi container checks passed."
  '';

  steam-asahi-bootstrap = pkgs.writeShellScriptBin "steam-asahi-bootstrap" ''
    set -eu

    SOURCE=/home/uynx/nixos-config/steam-asahi
    IMAGE=localhost/steam-asahi:44
    CONTAINER=steam-asahi
    LABEL=io.uynx.steam-asahi.config

    if [ ! -f "$SOURCE/Containerfile" ] || [ ! -f "$SOURCE/distrobox.ini" ]; then
      ${pkgs.libnotify}/bin/notify-send \
        "Steam setup unavailable" \
        "Missing the versioned steam-asahi container files."
      exit 1
    fi

    CONFIG_HASH=$(
      ${pkgs.coreutils}/bin/sha256sum \
        "$SOURCE/Containerfile" "$SOURCE/distrobox.ini" \
        | ${pkgs.coreutils}/bin/sha256sum \
        | ${pkgs.coreutils}/bin/cut -d' ' -f1
    )
    IMAGE_HASH=$(
      ${pkgs.docker}/bin/docker image inspect \
        --format "{{ index .Config.Labels \"$LABEL\" }}" \
        "$IMAGE" 2>/dev/null || true
    )
    REPLACE=0

    if [ "$IMAGE_HASH" != "$CONFIG_HASH" ]; then
      ${pkgs.docker}/bin/docker build \
        --label "$LABEL=$CONFIG_HASH" \
        --tag "$IMAGE" \
        --file "$SOURCE/Containerfile" \
        "$SOURCE"
      REPLACE=1
    fi

    IMAGE_ID=$(
      ${pkgs.docker}/bin/docker image inspect \
        --format '{{.Id}}' "$IMAGE"
    )
    if ! ${pkgs.docker}/bin/docker container inspect "$CONTAINER" >/dev/null 2>&1; then
      ${pkgs.distrobox}/bin/distrobox assemble create \
        --file "$SOURCE/distrobox.ini"
      REPLACE=0
    else
      CONTAINER_IMAGE_ID=$(
        ${pkgs.docker}/bin/docker container inspect \
          --format '{{.Image}}' "$CONTAINER"
      )
    fi
    if [ "$REPLACE" = 1 ] || \
       { [ -n "''${CONTAINER_IMAGE_ID:-}" ] && [ "$CONTAINER_IMAGE_ID" != "$IMAGE_ID" ]; }; then
      ${pkgs.distrobox}/bin/distrobox assemble create \
        --replace \
        --file "$SOURCE/distrobox.ini"
    fi

    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- rpm -q \
      muvm-0.6.0-3.fc44.aarch64 \
      fex-emu-2604-1.fc44.aarch64 \
      'fex-emu-rootfs-fedora-44^20260410.n.0-1.fc44.noarch' \
      virglrenderer-1.3.0-1.fc44.aarch64 \
      mesa-dri-drivers-26.1.4-1.fc44.aarch64 \
      mesa-vulkan-drivers-26.1.4-1.fc44.aarch64 \
      steam-0-14.fc44.noarch \
      xorg-x11-server-Xwayland-24.1.13-1.fc44.aarch64 >/dev/null
  '';

  # One reproducible Steam VM: Venus fixes DXVK black screens on the native DRM
  # path, while software CEF prevents steamwebhelper's GPU process crash loop.
  steam-asahi = pkgs.writeShellScriptBin "steam-asahi" ''
    set -eu

    APP_ID=''${1:-}
    STEAM_ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r '
      [.[] | select(((.class // "") | ascii_downcase) == "steam") | .address][0] // empty
    ' 2>/dev/null || true)
    if [ -n "$STEAM_ADDRESS" ]; then
      ${H} dispatch focuswindow "address:$STEAM_ADDRESS" >/dev/null 2>&1 || true
      if [ -n "$APP_ID" ]; then
        ${pkgs.libnotify}/bin/notify-send \
          "Steam is already open" \
          "Launch app $APP_ID from the existing Steam window."
      fi
      exit 0
    fi

    ${steam-asahi-bootstrap}/bin/steam-asahi-bootstrap

    STEAM_BIN=/home/uynx/.local/share/steam-asahi/home/.local/share/fex-steam/steam-launcher/bin_steam.sh
    if [ ! -x "$STEAM_BIN" ]; then
      ${pkgs.libnotify}/bin/notify-send \
        "Steam setup incomplete" \
        "Fedora's FEX Steam launcher is missing from the container home."
      exit 1
    fi

    STEAM_ARGS=-cef-disable-gpu
    if [ -n "$APP_ID" ]; then
      case "$APP_ID" in
        *[!0-9]*) exit 2 ;;
      esac
      STEAM_ARGS="$STEAM_ARGS -silent -applaunch $APP_ID"
    fi

    exec ${pkgs.distrobox}/bin/distrobox enter steam-asahi -- \
      /usr/bin/muvm --gpu-mode=venus -- FEXBash -c \
      "$STEAM_BIN $STEAM_ARGS"
  '';

  # Match Wine's virtual desktop to the target monitor's exact logical size.
  steam-launch = pkgs.writeShellScriptBin "steam-launch" ''
    set -eu

    APP_ID=$1
    if ! RESOLUTION=$(${H} monitors -j 2>/dev/null | ${J} -er '
      (if any(.name == "HDMI-A-1") then .[] | select(.name == "HDMI-A-1") else .[] | select(.focused) end)
      | select(.width > 0 and .height > 0 and .scale > 0)
      | "\((.width / .scale) | floor)x\((.height / .scale) | floor)"
    ' 2>/dev/null); then
      ${pkgs.libnotify}/bin/notify-send \
        "Steam game not launched" \
        "Could not read the target monitor resolution from Hyprland."
      exit 1
    fi
    WIDTH=''${RESOLUTION%x*}
    HEIGHT=''${RESOLUTION#*x}
    COMPAT="/home/uynx/.local/share/steam-asahi/home/.local/share/Steam/steamapps/compatdata"
    PREFIX="$COMPAT/''${APP_ID}/pfx"
    REG_FILE="$PREFIX/user.reg"
    if [ "$APP_ID" = 3540 ] && [ -f "$REG_FILE" ]; then
      STAMP=$(date +%s)
      # Older versions of this helper let printf consume registry backslashes.
      # Remove those malformed sections before writing the real Wine keys.
      sed -i -E \
        -e '/^\[SoftwareWineExplorer\]/,/^$/d' \
        -e '/^\[SoftwareWineExplorerDesktops\]/,/^$/d' \
        "$REG_FILE"
      if ! grep -Fq '[Software\\Wine\\Explorer]' "$REG_FILE"; then
        printf '\n%s %s\n#time=%s\n"Desktop"="Default"\n' \
          '[Software\\Wine\\Explorer]' "$STAMP" "$STAMP" >>"$REG_FILE"
      fi
      if grep -Fq '[Software\\Wine\\Explorer\\Desktops]' "$REG_FILE"; then
        sed -i -E \
          -e "s/\"Default\"=\"[0-9]+x[0-9]+\"/\"Default\"=\"''$RESOLUTION\"/g" \
          -e "s/\"Peggle\"=\"[0-9]+x[0-9]+\"/\"Peggle\"=\"''$RESOLUTION\"/g" \
          "$REG_FILE"
      else
        printf '\n%s %s\n#time=%s\n"Default"="%s"\n"Peggle"="%s"\n' \
          '[Software\\Wine\\Explorer\\Desktops]' \
          "$STAMP" "$STAMP" "$RESOLUTION" "$RESOLUTION" >>"$REG_FILE"
      fi
      sed -i -E \
        -e 's/"ScreenMode"=dword:[0-9a-fA-F]+/"ScreenMode"=dword:00000000/' \
        -e 's/"CustomCursors"=dword:[0-9a-fA-F]+/"CustomCursors"=dword:00000000/' \
        "$REG_FILE"
    fi

    PC_CONFIG=
    if [ "$APP_ID" = 32440 ]; then
      PC_CONFIG=$(find "$PREFIX/drive_c/users/steamuser/AppData/Local" \
        -type f -name pcconfig.txt -print -quit 2>/dev/null || true)
    fi
    if [ -n "$PC_CONFIG" ] && [ -f "$PC_CONFIG" ]; then
      chmod u+w "$PC_CONFIG"
      sed -i -E \
        -e "s/^ScreenWidth[[:space:]]+[0-9]+/ScreenWidth            ''$WIDTH/" \
        -e "s/^ScreenHeight[[:space:]]+[0-9]+/ScreenHeight           ''$HEIGHT/" \
        -e "s/^WindowWidth[[:space:]]+[0-9]+/WindowWidth            ''$WIDTH/" \
        -e "s/^WindowHeight[[:space:]]+[0-9]+/WindowHeight           ''$HEIGHT/" \
        -e "s/^WindowLeft[[:space:]]+[0-9]+/WindowLeft             0/" \
        -e "s/^WindowTop[[:space:]]+[0-9]+/WindowTop              0/" \
        -e "s/^Widescreen[[:space:]]+[0-9]+/Widescreen             1/" \
        "$PC_CONFIG"
      chmod u-w "$PC_CONFIG"
    fi

    # Fedora Asahi's Steam wrapper starts a new muvm on every invocation.
    # Starting it while Steam is open makes the existing client close/reopen.
    if ${H} clients -j 2>/dev/null | ${J} -e '
      any(.[]; ((.class // "") | ascii_downcase) == "steam")
    ' >/dev/null 2>&1; then
      ${pkgs.libnotify}/bin/notify-send \
        "Steam game prepared" \
        "Resolution updated. Launch app ''$APP_ID from the open Steam window."
      exit 0
    fi

    exec ${steam-asahi}/bin/steam-asahi "$APP_ID"
  '';

  steam-game-entries = pkgs.writeShellScriptBin "steam-game-entries" ''
    set -eu

    STEAM_ROOT=/home/uynx/.local/share/steam-asahi/home/.local/share/Steam
    APPLICATIONS="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    MANIFESTS=$(mktemp)
    GENERATED=$(mktemp -d)
    trap 'rm -f "$MANIFESTS"; rm -rf "$GENERATED"' EXIT

    {
      printf '%s\n' "$STEAM_ROOT"
      sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$STEAM_ROOT/steamapps/libraryfolders.vdf" 2>/dev/null || true
    } | while IFS= read -r LIBRARY; do
      [ -d "$LIBRARY" ] || continue
      find "$LIBRARY/steamapps" -maxdepth 1 -type f \
        -name 'appmanifest_*.acf' -print
    done | sort -u >"$MANIFESTS"

    while IFS= read -r MANIFEST; do
      APP_ID=$(sed -n 's/.*"appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$MANIFEST" | head -n 1)
      NAME=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
      OWNER=$(sed -n 's/.*"LastOwner"[[:space:]]*"\([0-9]*\)".*/\1/p' "$MANIFEST" | head -n 1)
      [ -n "$APP_ID" ] && [ -n "$NAME" ] && [ "$OWNER" != 0 ] || continue

      printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        "Name=$NAME" \
        'GenericName=Steam Game' \
        "Exec=${steam-launch}/bin/steam-launch $APP_ID" \
        'Icon=steam' \
        'Terminal=false' \
        'Categories=Game;' \
        "X-Steam-AppID=$APP_ID" \
        >"$GENERATED/steam-game-$APP_ID.desktop"
    done <"$MANIFESTS"

    mkdir -p "$APPLICATIONS"
    find "$APPLICATIONS" -maxdepth 1 -type f -name 'steam-game-*.desktop' -delete
    find "$GENERATED" -maxdepth 1 -type f -name '*.desktop' \
      -exec cp {} "$APPLICATIONS/" \;
  '';

  steam-fuzzel = pkgs.writeShellScriptBin "steam-fuzzel" ''
    ${steam-game-entries}/bin/steam-game-entries
    exec ${pkgs.fuzzel}/bin/fuzzel "$@"
  '';

  peggle = pkgs.writeShellScriptBin "peggle" ''
    exec ${steam-launch}/bin/steam-launch 3540
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
      steam-asahi
      steam-asahi-bootstrap
      steam-asahi-doctor
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
      steam-game-entries
      steam-fuzzel
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
      exec = "${steam-asahi}/bin/steam-asahi";
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
