{
  config,
  pkgs,
  lib,
  pkgs-stable,
  inputs,
  ...
}:

let
  H = "${pkgs.hyprland}/bin/hyprctl";
  J = "${pkgs.jq}/bin/jq";
  x86-pkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  x86-libgcc = x86-pkgs.stdenv.cc.cc.lib;
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
      gtk2-2.24.33-25.fc44.aarch64 \
      ibus-1.5.34-2.fc44.aarch64 \
      NetworkManager-1.56.1-2.fc44.aarch64 \
      openal-soft-1.24.2-6.fc44.aarch64 \
      libvdpau-1.5-11.fc44.aarch64 \
      libX11-devel-1.8.13-1.fc44.aarch64 \
      mesa-libGL-devel-26.1.4-1.fc44.aarch64 \
      steam-0-14.fc44.noarch \
      vulkan-loader-devel-1.4.341.0-1.fc44.aarch64 \
      xorg-x11-server-Xwayland-24.1.13-1.fc44.aarch64 >/dev/null
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -e /usr/lib64/dri/asahi_dri.so
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -e /usr/lib64/libvulkan_asahi.so
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -x /opt/steam-arm64/steamrtarm64/steam
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -x /usr/local/bin/box64
    printf '%s\n' "Steam Asahi container checks passed."
  '';

  steam-asahi-bootstrap = pkgs.writeShellScriptBin "steam-asahi-bootstrap" ''
    set -eu

    SOURCE=/home/uynx/nixos-config/steam-asahi
    IMAGE=localhost/steam-asahi:44
    CONTAINER=steam-asahi
    LABEL=io.uynx.steam-asahi.config

    if [ ! -f "$SOURCE/Containerfile" ] \
      || [ ! -f "$SOURCE/distrobox.ini" ] \
      || [ ! -f "$SOURCE/steam-guest-tune" ]; then
      ${pkgs.libnotify}/bin/notify-send \
        "Steam setup unavailable" \
        "Missing the versioned steam-asahi container files."
      exit 1
    fi

    CONFIG_HASH=$(
      ${pkgs.coreutils}/bin/sha256sum \
        "$SOURCE/Containerfile" "$SOURCE/distrobox.ini" \
        "$SOURCE/steam-guest-tune" \
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
      gtk2-2.24.33-25.fc44.aarch64 \
      ibus-1.5.34-2.fc44.aarch64 \
      NetworkManager-1.56.1-2.fc44.aarch64 \
      openal-soft-1.24.2-6.fc44.aarch64 \
      libvdpau-1.5-11.fc44.aarch64 \
      steam-0-14.fc44.noarch \
      xorg-x11-server-Xwayland-24.1.13-1.fc44.aarch64 >/dev/null
    ${pkgs.distrobox}/bin/distrobox enter "$CONTAINER" -- \
      test -x /opt/steam-arm64/steamrtarm64/steam
  '';

  # Steam, FEX, and muvm all live inside this dedicated container. Stopping the
  # container is the one reliable process boundary: it cannot leave a second
  # Steam client, FEX process, or Venus VM behind.
  steam-asahi-stop = pkgs.writeShellScriptBin "steam-asahi-stop" ''
    set -eu

    CONTAINER=steam-asahi
    if [ "$(${pkgs.docker}/bin/docker container inspect \
      --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" = true ]; then
      ${pkgs.docker}/bin/docker container stop --time 5 "$CONTAINER" >/dev/null
    fi

    # These sockets are runtime-only. Removing them after a full container stop
    # prevents an interrupted muvm session from blocking the next clean launch.
    rm -rf \
      "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/krun" \
      "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/muvm.lock"
  '';

  steam-compat-config = pkgs.writers.writePython3Bin "steam-compat-config" { } ''
    import re
    import sys
    from pathlib import Path

    config = Path(
        "/home/uynx/.local/share/steam-asahi/home/"
        ".local/share/Steam/config/config.vdf"
    )
    app_id, tool = sys.argv[1:3]
    if config.is_file():
        text = config.read_text()
    else:
        config.parent.mkdir(parents=True, exist_ok=True)
        text = (
            '"InstallConfigStore"\n{\n'
            '\t"Software"\n\t{\n'
            '\t\t"Valve"\n\t\t{\n'
            '\t\t\t"Steam"\n\t\t\t{\n'
            '\t\t\t}\n\t\t}\n\t}\n}\n'
        )


    def block_for_key(source, key, low=0, high=None):
        if high is None:
            high = len(source)
        match = re.search(r'"' + re.escape(key) + r'"\s*\{', source[low:high])
        if not match:
            return None
        opening = low + match.end() - 1
        depth = 0
        quoted = False
        escaped = False
        for pos in range(opening, high):
            char = source[pos]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return opening, pos
        return None


    region = (0, len(text))
    for key in ("InstallConfigStore", "Software", "Valve", "Steam"):
        found = block_for_key(text, key, region[0], region[1])
        if found is None:
            raise SystemExit(0)
        region = found

    mapping = block_for_key(text, "CompatToolMapping", region[0], region[1])
    entry = (
        f'\n\t\t\t\t\t"{app_id}"\n'
        "\t\t\t\t\t{\n"
        f'\t\t\t\t\t\t"name"\t\t"{tool}"\n'
        '\t\t\t\t\t\t"config"\t\t""\n'
        '\t\t\t\t\t\t"priority"\t\t"250"\n'
        "\t\t\t\t\t}\n\t\t\t\t"
    )
    if mapping is None:
        insertion = (
            '\n\t\t\t\t"CompatToolMapping"\n'
            "\t\t\t\t{" + entry + "}\n\t\t\t"
        )
        text = text[:region[1]] + insertion + text[region[1]:]
    else:
        app = block_for_key(text, app_id, mapping[0], mapping[1])
        if app is None:
            text = text[:mapping[0] + 1] + entry + text[mapping[0] + 1:]
        else:
            body = text[app[0]:app[1]]
            updated, count = re.subn(
                r'("name"\s*")[^"]*(")',
                rf'\g<1>{tool}\g<2>',
                body,
                count=1,
            )
            if count == 0:
                updated = body[:1] + f'\n\t"name"\t\t"{tool}"' + body[1:]
            text = text[:app[0]] + updated + text[app[1]:]

    temporary = config.with_suffix(".vdf.tmp")
    if not config.is_file() or config.read_text() != text:
        temporary.write_text(text)
        temporary.replace(config)
  '';

  # Forward commands from a short-lived native ARM64 guest to the running client.
  steam-asahi-remote = pkgs.writeShellScriptBin "steam-asahi-remote" ''
    set -eu

    TARGET=$1
    case "$TARGET" in
      ui)
        URL=steam://open/main
        ;;
      *[!0-9]*|"")
        exit 2
        ;;
      *)
        URL=steam://rungameid/$TARGET
        ;;
    esac

    STEAM_HOME=/home/uynx/.local/share/steam-asahi/home/.steam
    STEAM_BIN="$STEAM_HOME/root/steamrtarm64/steam"
    [ -p "$STEAM_HOME/steam.pipe" ] && [ -x "$STEAM_BIN" ]

    if [ "$TARGET" = 730 ]; then
      exec ${pkgs.distrobox}/bin/distrobox enter --no-workdir steam-asahi -- \
        /usr/bin/muvm -i -- "$STEAM_BIN" -applaunch "$TARGET" \
          -condebug +r_csgo_player_occlusion_query 0
    fi

    exec ${pkgs.distrobox}/bin/distrobox enter --no-workdir steam-asahi -- \
      /usr/bin/muvm -i -- "$STEAM_BIN" "$URL"
  '';

  steam-asahi-run = pkgs.writeShellScriptBin "steam-asahi-run" ''
    set -eu

    APP_ID=''${1:-}
    ${steam-asahi-bootstrap}/bin/steam-asahi-bootstrap
    ${steam-compat-config}/bin/steam-compat-config 32440 proton_10
    ${steam-compat-config}/bin/steam-compat-config 674940 box64_stickfight
    ${steam-compat-config}/bin/steam-compat-config 990080 proton_10

    STEAM_ROOT=/home/uynx/.local/share/steam-asahi/home/.local/share/Steam
    STEAM_HOME=/home/uynx/.local/share/steam-asahi/home/.steam
    STEAM_BIN="$STEAM_ROOT/steamrtarm64/steam"

    if [ ! -x "$STEAM_BIN" ]; then
      mkdir -p "$STEAM_ROOT"
      cp -a /opt/steam-arm64/steamrtarm64 "$STEAM_ROOT/"
    fi
    mkdir -p "$STEAM_ROOT/package" "$STEAM_HOME"
    printf '%s\n' publicbeta >"$STEAM_ROOT/package/beta"
    ln -sfn "$STEAM_ROOT" "$STEAM_HOME/root"
    ln -sfn "$STEAM_ROOT/linuxarm64" "$STEAM_HOME/sdkarm64"
    chmod -R u+rwX "$STEAM_ROOT/steamrtarm64"

    if [ -n "$APP_ID" ]; then
      case "$APP_ID" in
        *[!0-9]*) exit 2 ;;
      esac
    fi

    set -- /usr/bin/muvm --gpu-mode=venus
    if [ "$APP_ID" = 990080 ]; then
      # Hogwarts can otherwise let the Venus renderer grow beyond unified
      # memory headroom on this 16 GiB host.
      set -- "$@" --vram=4096
    fi
    set -- "$@" --execute-pre=/usr/local/libexec/steam-guest-tune -- \
      "$STEAM_BIN"
    if [ "$APP_ID" = 730 ]; then
      set -- "$@" -silent -applaunch "$APP_ID" \
        -condebug +r_csgo_player_occlusion_query 0
    elif [ -n "$APP_ID" ]; then
      set -- "$@" -silent -applaunch "$APP_ID"
    fi

    STATUS=0
    ${pkgs.distrobox}/bin/distrobox enter --no-workdir steam-asahi -- "$@" || STATUS=$?
    ${steam-asahi-stop}/bin/steam-asahi-stop
    exit "$STATUS"
  '';

  # The native ARM64 client avoids FEX's current Steam UI restart/focus loop;
  # Windows games still use Proton and FEX inside the same Venus VM.
  steam-asahi = pkgs.writeShellScriptBin "steam-asahi" ''
    set -eu

    STEAM_ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r '
      [.[] | select(((.class // "") | ascii_downcase) == "steam") | .address][0] // empty
    ' 2>/dev/null || true)
    if [ -n "$STEAM_ADDRESS" ]; then
      exec ${H} dispatch focuswindow "address:$STEAM_ADDRESS"
    fi

    if [ "$(${pkgs.docker}/bin/docker container inspect \
      --format '{{.State.Running}}' steam-asahi 2>/dev/null || true)" = true ] && \
       [ -p /home/uynx/.local/share/steam-asahi/home/.steam/steam.pipe ]; then
      ${steam-asahi-remote}/bin/steam-asahi-remote ui || true
      for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
        STEAM_ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r '
          [.[] | select(((.class // "") | ascii_downcase) == "steam") | .address][0] // empty
        ' 2>/dev/null || true)
        if [ -n "$STEAM_ADDRESS" ]; then
          exec ${H} dispatch focuswindow "address:$STEAM_ADDRESS"
        fi
        sleep 0.1
      done
      exit 0
    fi

    ${steam-asahi-stop}/bin/steam-asahi-stop
    exec ${steam-asahi-run}/bin/steam-asahi-run "$@"
  '';

  steam-game-watch = pkgs.writeShellScriptBin "steam-game-watch" ''
    set -u

    APP_ID=$1
    LOCK=$2
    if [ "$APP_ID" = 730 ]; then
      CLASS=cs2
    else
      CLASS=steam_app_$APP_ID
    fi
    cleanup() { rm -rf "$LOCK"; }
    trap cleanup EXIT
    printf '%s\n' "$$" >"$LOCK/pid"

    ADDRESS=
    for _ in $(${pkgs.coreutils}/bin/seq 1 600); do
      ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r --arg class "$CLASS" '
        [.[] | select(((.class // "") | ascii_downcase) == $class) | .address][0] // empty
      ' 2>/dev/null || true)
      [ -n "$ADDRESS" ] && break
      sleep 0.5
    done

    if [ -z "$ADDRESS" ]; then
      WINDOWS=$(${H} clients -j 2>/dev/null | ${J} -r '
        any(.[]; ((.class // "") | ascii_downcase) == "steam" or
                 ((.class // "") | ascii_downcase) == "cs2" or
                 ((.class // "") | test("^steam_app_[0-9]+$")))
      ' 2>/dev/null || echo true)
      [ "$WINDOWS" = true ] || ${steam-asahi-stop}/bin/steam-asahi-stop
      exit 0
    fi

    ${H} dispatch focuswindow "address:$ADDRESS" >/dev/null 2>&1 || true
    if [ "$APP_ID" != 674940 ]; then
      FULLSCREEN=$(${H} clients -j 2>/dev/null | ${J} -r --arg address "$ADDRESS" '
        [.[] | select(.address == $address) | .fullscreen][0] // 0
      ' 2>/dev/null || echo 0)
      if [ "$FULLSCREEN" = 0 ]; then
        ${H} dispatch fullscreen 0 >/dev/null 2>&1 || true
      fi
    fi

    while ${H} clients -j 2>/dev/null | ${J} -e --arg class "$CLASS" '
      any(.[]; ((.class // "") | ascii_downcase) == $class)
    ' >/dev/null 2>&1; do
      sleep 0.5
    done
    sleep 1

    WINDOWS=$(${H} clients -j 2>/dev/null | ${J} -r '
      any(.[]; ((.class // "") | ascii_downcase) == "steam" or
               ((.class // "") | ascii_downcase) == "cs2" or
               ((.class // "") | test("^steam_app_[0-9]+$")))
    ' 2>/dev/null || echo true)
    [ "$WINDOWS" = true ] || ${steam-asahi-stop}/bin/steam-asahi-stop
  '';

  # Match Wine's virtual desktop to the target monitor's exact logical size.
  steam-launch = pkgs.writeShellScriptBin "steam-launch" ''
    set -eu

    APP_ID=$1
    case "$APP_ID" in
      *[!0-9]*|"") exit 2 ;;
    esac

    if [ "$APP_ID" = 730 ]; then
      CLASS=cs2
    else
      CLASS=steam_app_$APP_ID
    fi
    GAME_ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r --arg class "$CLASS" '
      [.[] | select(((.class // "") | ascii_downcase) == $class) | .address][0] // empty
    ' 2>/dev/null || true)
    if [ -n "$GAME_ADDRESS" ]; then
      exec ${H} dispatch focuswindow "address:$GAME_ADDRESS"
    fi

    LOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/steam-asahi-launch-$APP_ID"
    if ! mkdir "$LOCK" 2>/dev/null; then
      WATCH_PID=$(cat "$LOCK/pid" 2>/dev/null || true)
      if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
        ${pkgs.libnotify}/bin/notify-send \
          "Steam game is already launching" \
          "Waiting for app $APP_ID."
        exit 0
      fi
      rm -rf "$LOCK"
      mkdir "$LOCK"
    fi
    WATCH_STARTED=0
    cleanup_launch() {
      [ "$WATCH_STARTED" = 1 ] || rm -rf "$LOCK"
    }
    trap cleanup_launch EXIT

    case "$APP_ID" in
      32440 | 990080)
        ${steam-compat-config}/bin/steam-compat-config "$APP_ID" proton_10
        ;;
      674940)
        ${steam-compat-config}/bin/steam-compat-config "$APP_ID" box64_stickfight
        ;;
    esac

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

    if [ "$APP_ID" = 730 ]; then
      CS2_VIDEO=/home/uynx/.local/share/steam-asahi/home/.local/share/Steam/userdata/483670283/730/local/cfg/cs2_video.txt
      if ${H} monitors -j 2>/dev/null | ${J} -e 'any(.name == "HDMI-A-1")' >/dev/null; then
        CS2_MONITOR=1
      else
        CS2_MONITOR=0
      fi
      CS2_REFRESH=$(${H} monitors -j 2>/dev/null | ${J} -r '
        (if any(.name == "HDMI-A-1") then .[] | select(.name == "HDMI-A-1") else .[] | select(.focused) end)
        | .refreshRate | round
      ' 2>/dev/null || echo 60)
      if [ -f "$CS2_VIDEO" ]; then
        sed -i -E \
          -e "s/(\"setting.defaultres\"[[:space:]]+\")[0-9]+/\1$WIDTH/" \
          -e "s/(\"setting.defaultresheight\"[[:space:]]+\")[0-9]+/\1$HEIGHT/" \
          -e "s/(\"setting.refreshrate_numerator\"[[:space:]]+\")[0-9]+/\1$((CS2_REFRESH * 1000))/" \
          -e 's/("setting.refreshrate_denominator"[[:space:]]+")[0-9]+/\11000/' \
          -e "s/(\"setting.monitor_index\"[[:space:]]+\")[0-9]+/\1$CS2_MONITOR/" \
          -e 's/("setting.aspectratiomode"[[:space:]]+")[0-9]+/\11/' \
          "$CS2_VIDEO"
      fi
    fi

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
        -e 's/"ScreenMode"=dword:[0-9a-fA-F]+/"ScreenMode"=dword:00000001/' \
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

    ${pkgs.util-linux}/bin/setsid \
      ${steam-game-watch}/bin/steam-game-watch "$APP_ID" "$LOCK" \
      >/dev/null 2>&1 &
    WATCH_STARTED=1

    CONTAINER_RUNNING=$(${pkgs.docker}/bin/docker container inspect \
      --format '{{.State.Running}}' steam-asahi 2>/dev/null || true)
    if [ "$CONTAINER_RUNNING" = true ]; then
      for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
        [ -p /home/uynx/.local/share/steam-asahi/home/.steam/steam.pipe ] && break
        sleep 0.1
      done
      if [ -p /home/uynx/.local/share/steam-asahi/home/.steam/steam.pipe ]; then
        ${steam-asahi-remote}/bin/steam-asahi-remote "$APP_ID"
        exit 0
      fi

      STEAM_ADDRESS=$(${H} clients -j 2>/dev/null | ${J} -r '
        [.[] | select(((.class // "") | ascii_downcase) == "steam") | .address][0] // empty
      ' 2>/dev/null || true)
      if [ -n "$STEAM_ADDRESS" ]; then
        ${pkgs.libnotify}/bin/notify-send \
          "Steam game not launched" \
          "Steam is still starting; try again in a moment."
        exit 1
      fi
      ${steam-asahi-stop}/bin/steam-asahi-stop
    fi

    exec ${steam-asahi-run}/bin/steam-asahi-run "$APP_ID"
  '';

  hypr-close-active = pkgs.writeShellScriptBin "hypr-close-active" ''
    set -eu

    ACTIVE=$(${H} activewindow -j 2>/dev/null || echo '{}')
    CLASS=$(printf '%s' "$ACTIVE" | ${J} -r '.class // ""' 2>/dev/null || true)
    ADDRESS=$(printf '%s' "$ACTIVE" | ${J} -r '.address // ""' 2>/dev/null || true)
    case "$CLASS" in
      steam|Steam)
        # Keep the shared client alive; quit it through Steam's own menu.
        exit 0
        ;;
      steam_app_[0-9]*|cs2)
        if [ -n "$ADDRESS" ]; then
          ${H} dispatch closewindow "address:$ADDRESS" >/dev/null 2>&1 || true
          for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
            STILL_OPEN=$(${H} clients -j 2>/dev/null | ${J} -r --arg address "$ADDRESS" '
              any(.[]; .address == $address)
            ' 2>/dev/null || echo true)
            [ "$STILL_OPEN" = true ] || break
            sleep 0.1
          done
        fi
        STEAM_OPEN=$(${H} clients -j 2>/dev/null | ${J} -r '
          any(.[]; ((.class // "") | ascii_downcase) == "steam")
        ' 2>/dev/null || echo false)
        [ "$STEAM_OPEN" = true ] && exit 0
        exec ${steam-asahi-stop}/bin/steam-asahi-stop
        ;;
      *)
        exec ${H} dispatch closewindow active
        ;;
    esac
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
      case "$NAME" in
        Proton\ *|Steam\ Linux\ Runtime*|Steamworks\ Common\ Redistributables)
          continue
          ;;
      esac

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
    file.".local/share/steam-asahi/home/.local/share/Steam/steamapps/common/Counter-Strike Global Offensive/game/csgo/cfg/autoexec.cfg" =
      {
        force = true;
        text = ''
          // Venus can lose CS2's player-occlusion query pool during match load.
          r_csgo_player_occlusion_query 0
        '';
      };
    file.".local/bin/hypr-close-active".source = "${hypr-close-active}/bin/hypr-close-active";
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
      steam-asahi-stop
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
      hypr-close-active
      steam-game-entries
      steam-fuzzel
      workspace-switcher
      update-brave-origin
      obs-studio
      vesktop
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
      ".local/share/steam-asahi/home/.local/share/Steam/compatibilitytools.d/Box64-StickFight/compatibilitytool.vdf".text =
        ''
          "compatibilitytools"
          {
            "compat_tools"
            {
              "box64_stickfight"
              {
                "install_path" "."
                "display_name" "Box64 Stick Fight"
                "from_oslist" "windows"
                "to_oslist" "linux"
              }
            }
          }
        '';
      ".local/share/steam-asahi/home/.local/share/Steam/compatibilitytools.d/Box64-StickFight/toolmanifest.vdf".text =
        ''
          "manifest"
          {
            "commandline" "/proton run"
            "commandline_getnativepath" "/proton getnativepath"
            "commandline_getcompatpath" "/proton getcompatpath"
            "commandline_waitforexitandrun" "/proton waitforexitandrun"
          }
        '';
      ".local/share/steam-asahi/home/.local/share/Steam/compatibilitytools.d/Box64-StickFight/proton" = {
        executable = true;
        text = ''
          #!/bin/sh
          set -eu

          ACTION=''${1:-run}
          [ "$#" -eq 0 ] || shift
          case "$ACTION" in
            getnativepath|getcompatpath)
              printf '%s\n' "''${1:-}"
              exit 0
              ;;
            run|waitforexitandrun)
              ;;
            *)
              exit 2
              ;;
          esac
          [ "$#" -gt 0 ]
          GAME=$1
          export MESA_LOADER_DRIVER_OVERRIDE=zink
          export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/virtio_icd.aarch64.json
          PROTON=/home/uynx/.local/share/steam-asahi/home/.local/share/Steam/steamapps/common/Proton\ 10.0/files
          export WINEPREFIX=/home/uynx/.local/share/steam-asahi/home/.local/share/Steam/steamapps/compatdata/674940/pfx
          export WINEDEBUG=-all
          export WINEDLLPATH="$PROTON/lib/vkd3d:$PROTON/lib/wine"
          export LD_LIBRARY_PATH="$PROTON/lib/x86_64-linux-gnu:$PROTON/lib/i386-linux-gnu:${x86-libgcc}/lib:/usr/lib64:/usr/lib:''${LD_LIBRARY_PATH:-}"
          unset LD_PRELOAD
          export SteamAppId=674940
          export SteamGameId=674940
          export BOX64_DYNAREC_STRONGMEM=1
          export BOX64_DYNAREC_BIGBLOCK=0
          export BOX64_NOGTK=1

          exec /usr/local/bin/box64 "$PROTON/bin/wine" \
            "$GAME" -force-d3d9 -popupwindow -screen-fullscreen 0
        '';
      };
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
    activation.generateSteamGameEntries = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${steam-game-entries}/bin/steam-game-entries
    '';
  };

  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  xdg.desktopEntries = {
    steam = {
      name = "Steam";
      genericName = "Games Store";
      exec = "${steam-asahi}/bin/steam-asahi";
      icon = "steam";
      terminal = false;
      categories = [
        "Network"
        "FileTransfer"
        "Game"
      ];
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
