{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.devcontainer;
  settingsFormat = pkgs.formats.json { };
  networkModeArgs = lib.optionals (cfg.networkMode == "host") [ "--network=host" ];
  podmanSettings = lib.optionalAttrs (cfg.mode == "podman" || cfg.mode == "builtin") {
    containerUser = "vscode";
    containerEnv = {
      HOME = "/home/vscode";
    };
    runArgs = [
      "--userns=keep-id"
    ] ++ networkModeArgs;
  };
  dockerSettings = lib.optionalAttrs (cfg.mode == "docker") (
    lib.optionalAttrs (networkModeArgs != [ ]) {
      runArgs = networkModeArgs;
    }
  );
  filteredSettings =
    cfg.settings
    // podmanSettings
    // dockerSettings
    // {
      customizations = cfg.settings.customizations // {
        vscode = cfg.settings.customizations.vscode // {
          extensions = lib.filter (ext: ext != "vscodevim.vim") cfg.settings.customizations.vscode.extensions;
        };
      };
    }
    // lib.optionalAttrs (lib.elem "mkhl.direnv" cfg.settings.customizations.vscode.extensions) {
      postCreateCommand = "direnv allow";
    };
  file = settingsFormat.generate "devcontainer.json" filteredSettings;
  inherit (lib)
    types
    mkOption
    mkIf
    optionals
    ;
  podmanSetupScript =
    let
      policyConf = pkgs.writeText "policy.conf" ''
        {"default":[{"type":"insecureAcceptAnything"}],"transports":{"docker-daemon":{"":[{"type":"insecureAcceptAnything"}]}}}
      '';
      registriesConf = pkgs.writeText "registries.conf" ''
        [registries]
        [registries.block]
        registries = []
        [registries.insecure]
        registries = []
        [registries.search]
        registries = ["docker.io", "quay.io"]
      '';
      storageConf = pkgs.writeText "storage.conf" ''
        [storage]
        driver = "overlay"
      '';
      containersConf = pkgs.writeText "containers.conf" ''
        [engine]
        helper_binaries_dir = ["${pkgs.podman}/libexec/podman","${pkgs.crun}/bin","${pkgs.fuse-overlayfs}/bin"]
        runtime = "crun"
        [containers]
        pids_limit = 0
      '';
    in
    pkgs.writeScript "podman-setup" ''
      #!${pkgs.runtimeShell}
      if ! test -f ~/.config/containers/policy.json; then
        install -Dm755 ${policyConf} ~/.config/containers/policy.json
      fi
      if ! test -f ~/.config/containers/registries.conf; then
        install -Dm755 ${registriesConf} ~/.config/containers/registries.conf
      fi
      if ! test -f ~/.config/containers/storage.conf; then
        install -Dm755 ${storageConf} ~/.config/containers/storage.conf
      fi
      install -Dm755 ${containersConf} ~/.config/containers/containers.conf
      if command -v "systemctl" >/dev/null 2>&1; then
        mkdir -p ~/.config/systemd/user
        ln -sf ${pkgs.podman}/share/systemd/user/podman.socket ~/.config/systemd/user/podman.socket
        ln -sf ${pkgs.podman}/share/systemd/user/podman.service ~/.config/systemd/user/podman.service
        systemctl --user start podman.socket
      fi
    '';
in
{
  disabledModules = [
    (inputs.devenv.modules + "/integrations/devcontainer.nix")
  ];
  options.devcontainer = {
    enable = lib.mkEnableOption "generation .devcontainer.json for devenv integration";

    mode = mkOption {
      type = types.enum [
        "podman"
        "docker"
        "builtin"
      ];
      default = "docker";
      description = "The container runtime mode to use";
    };

    networkMode = lib.mkOption {
      type = lib.types.enum [
        "bridge"
        "host"
      ];
      default = "bridge";
      description = ''
        Network mode for the container.
        - "bridge": Use default network mode
        - "host": Use host networking (shares the host's network namespace)
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;

        options.image = lib.mkOption {
          type = lib.types.str;
          default = "ghcr.io/cachix/devenv/devcontainer:latest";
          description = ''
            The name of an image in a container registry.
          '';
        };

        options.overrideCommand = lib.mkOption {
          type = lib.types.anything;
          default = false;
          description = ''
            Override the default command.
          '';
        };

        options.updateContentCommand = lib.mkOption {
          type = lib.types.anything;
          default = "devenv shell -- echo Ready.";
          description = ''
            A command to run after the container is created.
          '';
        };

        options.customizations.vscode.extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "mkhl.direnv"
            "bbenoist.Nix"
          ];
          description = ''
            A list of pre-installed VS Code extensions.
          '';
        };
      };

      default = { };

      description = ''
        Devcontainer settings.
      '';
    };
  };

  config = lib.mkIf config.devcontainer.enable {
    packages =
      [ ]
      ++ (optionals (cfg.mode == "builtin") [
        (pkgs.vscode-with-extensions.override {
          vscode = pkgs.vscode;
          vscodeExtensions =
            [
              pkgs.vscode-extensions.ms-vscode-remote.remote-containers
            ]
            ++ optionals (lib.elem "vscodevim.vim" cfg.settings.customizations.vscode.extensions) [
              pkgs.vscode-extensions.vscodevim.vim
            ];
        })
      ])
      ++ (optionals (cfg.mode == "builtin") [
        pkgs.podman
        pkgs.crun
        pkgs.conmon
        pkgs.skopeo
        pkgs.slirp4netns
        pkgs.fuse-overlayfs
      ]);
    enterShell =
      ''
        cat ${file} > ${config.env.DEVENV_ROOT}/.devcontainer.json
      ''
      + (lib.optionalString (cfg.mode == "builtin") ''
        ${podmanSetupScript}
      '');
  };
}
