{
  config,
  pkgs,
  lib,
  pkgs-stable,
  ...
}:

let
  gitKey = "~/.ssh/id_ed25519.pub";
in
{
  home = {
    username = "uynx";
    homeDirectory = "/home/uynx";
    stateVersion = "25.11";
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      AGY_CLI_DISABLE_AUTO_UPDATE = "true";
    };
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.capitaine-cursors;
    name = "capitaine-cursors";
    size = 24;
  };

  home.packages = with pkgs; [
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
      withPerl = true;
      withNodeJs = true;
      withPython3 = true;
      withRuby = true;
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
    ast-grep
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

    (pkgs-stable.texlive.withPackages (ps: with ps; [
      scheme-full
      biber
    ]))

    melonds
    proton-pass-cli
    qbittorrent
    wireshark
    dive
    swi-prolog

    libreoffice

    tmux
    tmuxPlugins.sensible
    tmuxPlugins.vim-tmux-navigator
    tmuxPlugins.resurrect
    tmuxPlugins.continuum
  ];

  home.file = {
    ".config/nvim".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nvim";
    ".local/share/nvim/site/parser/norg.so".source =
      "${pkgs.tree-sitter-grammars.tree-sitter-norg}/parser";

    ".config/ghostty/config".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/ghostty_config";

    ".config/hypr/hyprland.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/hypr/hyprland.conf";

    ".config/waybar".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/waybar";

    ".config/tmux".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/tmux";

    ".agents/skills".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/skills";

    ".agents/AGENTS.md".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/AGENTS.md";
  };

  programs = {
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        editor = "nvim";
      };
    };

    ghostty = {
      enable = true;
      package = pkgs.ghostty;
    };

    waybar.enable = true;

    fastfetch.enable = true;
    bun.enable = true;
    lazydocker.enable = true;
    java.enable = true;
    cargo.enable = true;

    vscodium = {
      enable = true;
      package = pkgs.vscodium;
    };

    # discord = {
    #   enable = true;
    # };

    man = {
      enable = true;
      generateCaches = true;
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    yazi = {
      enable = true;
      enableFishIntegration = true;
      shellWrapperName = "y";
      settings = {
        manager = {
          show_hidden = true;
          sort_by = "modified";
          sort_dir_first = true;
        };
      };
    };

    bat.enable = true;

    eza = {
      enable = true;
      enableFishIntegration = true;
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

    atuin = {
      enable = true;
      enableFishIntegration = true;
    };

    fish = {
      enable = true;

      interactiveShellInit = ''
        set -g fish_greeting ""
        fish_vi_key_bindings
      '';

      functions = {
        reb = {
          body = ''
            set -l target "uynx"
            if test (count $argv) -gt 0
                set target $argv[1]
            end
            sudo nixos-rebuild switch --flake ~/nixos-config#$target
          '';
        };
      };

      shellAliases = {
        update = "nix flake update --flake ~/nixos-config";

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
      enableFishIntegration = true;
      settings = {
        add_newline = false;
        command_timeout = 3000;
      };
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
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
      package = pkgs.brave;
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
      enableFishIntegration = true;
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
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
          signingkey = gitKey;
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

  home.activation.copilotBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    AUTH_DB="${config.home.homeDirectory}/.config/github-copilot/auth.db"
    HOSTS_JSON="${config.home.homeDirectory}/.config/github-copilot/hosts.json"
    if [ -f "$AUTH_DB" ]; then
      TOKEN=$(${pkgs.sqlite}/bin/sqlite3 "$AUTH_DB" "SELECT cast(token_ciphertext as text) FROM oauth_tokens LIMIT 1;" 2>/dev/null)
      if [ -n "$TOKEN" ]; then
        mkdir -p "$(dirname "$HOSTS_JSON")"
        printf '{\n  "github.com": {\n    "oauth_token": "%s"\n  }\n}\n' "$TOKEN" > "$HOSTS_JSON"
        chmod 600 "$HOSTS_JSON"
      fi
    fi
  '';

  home.activation.createRequiredDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/ai_memory/concepts"
    mkdir -p "${config.home.homeDirectory}/ai_memory/journal"
    mkdir -p "${config.home.homeDirectory}/dotfiles"
    mkdir -p "${config.home.homeDirectory}/nixos-config"
  '';
}
