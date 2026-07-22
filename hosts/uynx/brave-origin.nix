{ lib
, stdenv
, fetchurl
, dpkg
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, gtk4
, libX11
, libxscrnsaver
, libXcomposite
, libXcursor
, libXdamage
, libXext
, libXfixes
, libXi
, libXrandr
, libXrender
, libXtst
, libdrm
, libuuid
, libxkbcommon
, libxshmfence
, libgbm
, nspr
, nss
, pango
, pipewire
, udev
, wayland
, xdg-utils
, wrapGAppsHook3
, makeShellWrapper
, libGL
, libpulseaudio
, coreutils
, libxcb
}:

let
  version = "1.92.143";

  arch = if stdenv.hostPlatform.system == "aarch64-linux" then "arm64"
         else if stdenv.hostPlatform.system == "x86_64-linux" then "amd64"
         else throw "Unsupported platform: ${stdenv.hostPlatform.system}";

  hash = if arch == "arm64" then "sha256-kGKyW4GOD4UO2Lp0sxesk8+XZJvK5q67gaJONPb3Fpg="
         else "sha256-65453t8O/sCNfiM71ZwX6EDrEyTsvh1CGCsjh89XKg4=";

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libX11
    libGL
    libxkbcommon
    libxscrnsaver
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libxshmfence
    libXtst
    libuuid
    libgbm
    nspr
    nss
    pango
    pipewire
    udev
    wayland
    libpulseaudio
    libxcb
  ];

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;
  binpath = lib.makeBinPath deps;

in
stdenv.mkDerivation rec {
  pname = "brave-origin";
  inherit version;

  src = fetchurl {
    url = "https://brave-browser-apt-release.s3.brave.com/pool/main/b/brave-origin/brave-origin_${version}_${arch}.deb";
    inherit hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;

  nativeBuildInputs = [ dpkg wrapGAppsHook3 makeShellWrapper ];

  buildInputs = [
    glib
    gtk3
    gtk4
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out $out/bin

    cp -R usr/share $out
    cp -R opt/ $out/opt

    export BINARYWRAPPER=$out/opt/brave.com/brave-origin/brave-origin

    # Fix path to bash in the launch wrapper
    substituteInPlace $BINARYWRAPPER \
        --replace "/bin/bash" "${stdenv.shell}" \
        --replace "CHROME_WRAPPER" "WRAPPER"

    ln -sf $BINARYWRAPPER $out/bin/brave-origin

    # Patch ELF executables
    for exe in $out/opt/brave.com/brave-origin/{brave,chrome_crashpad_handler}; do
        patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            --set-rpath "${rpath}" $exe
    done

    # Fix paths in desktop entries
    substituteInPlace $out/share/applications/{brave-origin,com.brave.Origin}.desktop \
        --replace "/usr/bin/brave-origin-stable" "$out/bin/brave-origin" \
        --replace "/usr/bin/brave-origin" "$out/bin/brave-origin"

    # Replace xdg-settings and xdg-mime
    ln -sf ${xdg-utils}/bin/xdg-settings $out/opt/brave.com/brave-origin/xdg-settings
    ln -sf ${xdg-utils}/bin/xdg-mime $out/opt/brave.com/brave-origin/xdg-mime

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${binpath}
      --suffix PATH : ${lib.makeBinPath [ xdg-utils coreutils ]}
      --set CHROME_WRAPPER brave-origin
      --add-flags "--ozone-platform-hint=auto"
    )
  '';

  meta = with lib; {
    homepage = "https://brave.com/";
    description = "Brave Origin: Minimalist, adblock-focused version of Brave Browser";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" "x86_64-linux" ];
    mainProgram = "brave-origin";
  };
}
