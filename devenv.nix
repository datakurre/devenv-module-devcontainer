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
  
  # Compute final settings with tweaks applied
  computedSettings =
    let
      # Start with base settings
      baseSettings = cfg.settings;
      
      # Apply GPG agent tweak
      gpgSettings = lib.optionalAttrs (lib.elem "gpg-agent" cfg.tweaks) {
        mounts = [
          "source=\${localEnv:XDG_RUNTIME_DIR}/gnupg/S.gpg-agent,target=/run/host-gpg-agent,type=bind,readonly"
        ];
        remoteEnv.GPG_TTY = "/dev/pts/0";
        postStartCommand = "mkdir -p /home/vscode/.gnupg && rm -f /home/vscode/.gnupg/S.gpg-agent && ln -s /run/host-gpg-agent /home/vscode/.gnupg/S.gpg-agent";
      };
      
      # Apply netrc tweak
      netrcSettings = lib.optionalAttrs (lib.elem "netrc" cfg.tweaks) (
        assert lib.assertMsg (cfg.netrc != null) "devcontainer.netrc must be set when using 'netrc' tweak";
        {
          mounts = [
            "source=${cfg.netrc},target=/home/vscode/.netrc,type=bind,readonly"
          ];
          onCreateCommand = "mkdir -p /home/vscode/.config/nix && echo 'extra-sandbox-paths = /tmp/.netrc' > /home/vscode/.config/nix/nix.conf && cat /home/vscode/.netrc > /tmp/.netrc";
          containerEnv.NETRC = "/tmp/.netrc";
        }
      );
      
      # Apply podman/rootless tweaks
      podmanSettings = lib.optionalAttrs (lib.elem "rootless" cfg.tweaks || lib.elem "podman" cfg.tweaks) {
        containerUser = "vscode";
        containerEnv.HOME = "/home/vscode";
        runArgs = [ "--userns=keep-id" ];
      };
      
      # Apply host network mode
      hostNetworkSettings = lib.optionalAttrs (cfg.networkMode == "host") {
        runArgs = [ "--network=host" ];
      };
      
      # Merge all settings with proper list concatenation and attrset merging
      mergedSettings = lib.recursiveUpdate baseSettings (
        lib.recursiveUpdate (
          lib.recursiveUpdate (
            lib.recursiveUpdate gpgSettings netrcSettings
          ) podmanSettings
        ) hostNetworkSettings
      );
      
      # Special handling for lists - concatenate instead of replace
      finalMounts = (baseSettings.mounts or [])
        ++ (gpgSettings.mounts or [])
        ++ (netrcSettings.mounts or []);
        
      finalRunArgs = (baseSettings.runArgs or [])
        ++ (podmanSettings.runArgs or [])
        ++ (hostNetworkSettings.runArgs or []);
        
      finalContainerEnv = (baseSettings.containerEnv or {})
        // (podmanSettings.containerEnv or {})
        // (netrcSettings.containerEnv or {});
        
      finalRemoteEnv = (baseSettings.remoteEnv or {})
        // (gpgSettings.remoteEnv or {});
        
      finalOnCreateCommand = netrcSettings.onCreateCommand or baseSettings.onCreateCommand or "";
        
    in
      mergedSettings // {
        mounts = finalMounts;
        runArgs = finalRunArgs;
        containerEnv = finalContainerEnv;
        remoteEnv = finalRemoteEnv;
        onCreateCommand = finalOnCreateCommand;
      };

  devcontainerSettings =
    let
      # Get the default extensions and user extensions
      defaultExtensions = [
        "mkhl.direnv"
        "bbenoist.Nix"
      ];
      userExtensions = computedSettings.customizations.vscode.extensions or [ ];
      # Merge extensions: defaults + user extensions, then remove vscodevim.vim
      allExtensions = lib.unique (defaultExtensions ++ userExtensions);
      filteredExtensions = lib.filter (ext: ext != "vscodevim.vim") allExtensions;

      # Then apply customizations that need special handling
      finalSettings =
        computedSettings
        // {
          customizations = computedSettings.customizations // {
            vscode =
              computedSettings.customizations.vscode
              // {
                extensions = filteredExtensions;
              }
              // lib.optionalAttrs (cfg.networkMode == "host") {
                settings = computedSettings.customizations.vscode.settings or { } // {
                  "remote.autoForwardPorts" = false;
                };
              };
          };
        }
        # Only set postCreateCommand if not already explicitly set by user
        // lib.optionalAttrs (!(computedSettings ? postCreateCommand) || computedSettings.postCreateCommand == "direnv allow") {
          postCreateCommand = "direnv allow";
        };
    in
    finalSettings;
  file = settingsFormat.generate "devcontainer.json" devcontainerSettings;
  inherit (lib)
    types
    mkOption
    mkIf
    optionals
    ;
  podmanSetupScript =
    let
      policyConf = pkgs.writeText "policy.conf" ''
        {"default":[{"type":"insecureAcceptAnything"}],"transports":{"default-daemon":{"":[{"type":"insecureAcceptAnything"}]}}}
      '';
      registriesConf = pkgs.writeText "registries.conf" ''
        [registries]
        [registries.block]
        registries = []
        [registries.insecure]
        registries = []
        [registries.search]
        registries = ["default.io", "quay.io"]
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

    tweaks = mkOption {
      type = types.listOf (
        types.enum [
          "rootless"
          "podman"
          "vscode"
          "gpg-agent"
          "netrc"
        ]
      );
      default = [ ];
      description = "List of tweaks to apply to the devcontainer configuration.";
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

    netrc = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the .netrc file to mount into the container at /home/vscode/.netrc.
        Required when using the 'netrc' tweak.
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

        options.mounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            List of mount specifications for the container.
          '';
        };

        options.containerEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Environment variables to set in the container.
          '';
        };

        options.runArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional arguments to pass to the container runtime.
          '';
        };

        options.remoteEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Environment variables to set in the remote environment.
          '';
        };

        options.postStartCommand = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Command to run after the container starts.
          '';
        };

        options.onCreateCommand = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Command to run when the container is created.
          '';
        };

        options.postCreateCommand = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "direnv allow";
          description = ''
            Command to run after the container is created.
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
      ++ (optionals (lib.elem "vscode" cfg.tweaks) [
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
      ++ (optionals (lib.elem "podman" cfg.tweaks) [
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
      + (lib.optionalString (lib.elem "podman" cfg.tweaks) ''
        ${podmanSetupScript}
      '');
  };
}
