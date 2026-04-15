{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-devcontainer = import inputs.devenv-module-devcontainer-nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  allServices = import ./services;
  cfg = config.devcontainer;
  firewall = import ./devcontainer-firewall.nix {
    inherit pkgs lib cfg;
  };
  inherit (firewall)
    firewallEnabled
    firewallScript
    profileScript
    removeSudoScript
    ;
  settingsFormat = pkgs.formats.json { };

  # Tweak helpers
  tweak-gpg-agent = import ./tweaks/gpg-agent.nix { inherit lib; };
  tweak-netrc = import ./tweaks/netrc.nix { inherit lib; };
  tweak-pass = import ./tweaks/pass.nix { inherit lib; };
  tweak-rootless = import ./tweaks/rootless.nix { inherit lib; };
  tweak-podman = import ./tweaks/podman.nix { inherit lib pkgs; };
  tweak-vscode = import ./tweaks/vscode.nix {
    inherit lib;
    pkgsDevcontainer = pkgs-devcontainer;
  };
  tweak-cli = import ./tweaks/cli.nix {
    inherit lib;
    pkgsDevcontainer = pkgs-devcontainer;
  };

  # Fetch each vsix into the Nix store at build time
  vsixFetched = map (
    entry:
    let
      url = if builtins.isAttrs entry then entry.url else entry;
      sha256 = if builtins.isAttrs entry && entry ? sha256 then entry.sha256 else null;
      fetched =
        if sha256 != null then builtins.fetchurl { inherit url sha256; } else builtins.fetchurl url;
      filename = lib.last (lib.splitString "/" url);
    in
    {
      storePath = fetched;
      containerPath = "/run/host-vsix/${filename}";
      mount = "source=${fetched},target=/run/host-vsix/${filename},type=bind,readonly";
    }
  ) cfg.vsix;

  vsixMounts = map (e: e.mount) vsixFetched;
  vsixContainerPaths = map (e: e.containerPath) vsixFetched;

  # Compute final settings with tweaks applied
  computedSettings =
    let
      # Start with base settings
      baseSettings = cfg.settings;

      gpgSettings = tweak-gpg-agent.settings cfg;
      netrcSettings = tweak-netrc.settings cfg;
      passSettings = tweak-pass.settings cfg;
      podmanSettings = tweak-rootless.settings cfg;

      # Apply host network mode
      hostNetworkSettings = lib.optionalAttrs (cfg.network.mode == "host") {
        runArgs = [ "--network=host" ];
      };

      # Apply network=none mode (complete network isolation)
      noneNetworkSettings = lib.optionalAttrs (cfg.network.mode == "none") {
        runArgs = [ "--network=none" ];
      };

      # Apply named network mode
      isNamedNetwork = cfg.network.mode == "named";
      namedNetworkSettings = lib.optionalAttrs isNamedNetwork (
        assert lib.assertMsg (
          cfg.network.name != null
        ) "devcontainer.network.name must be set when network.mode = \"named\"";
        {
          runArgs = [ "--network=${cfg.network.name}" ];
        }
      );

      # Apply container name
      containerNameSettings = lib.optionalAttrs (cfg.name != null) {
        runArgs = [ "--name=${cfg.name}" ];
      };

      # Apply container hostname
      hostnameSettings = lib.optionalAttrs (cfg.network.hostname != null) {
        runArgs = [ "--hostname=${cfg.network.hostname}" ];
      };

      # allowedHosts: bind-mount the generated firewall script and request NET_ADMIN
      firewallMounts =
        if firewallEnabled && !(cfg.network.mode == "bridge" || cfg.network.mode == "named") then
          throw "devcontainer.network.allowedHosts/allowedServices requires network.mode = \"bridge\" (default) or \"named\", but is set to \"${cfg.network.mode}\""
        else
          lib.optional firewallEnabled "source=${firewallScript},target=/run/devcontainer-firewall,type=bind,readonly"
          ++ lib.optional firewallEnabled "source=${removeSudoScript},target=/run/devcontainer-remove-sudo,type=bind,readonly"
          ++ lib.optional firewallEnabled "source=${profileScript},target=/etc/profile.d/devcontainer-firewall.sh,type=bind,readonly";

      firewallRunArgs = lib.optional firewallEnabled "--cap-add=NET_ADMIN";

      # Merge all settings with proper list concatenation and attrset merging
      mergedSettings = lib.recursiveUpdate baseSettings (
        lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate gpgSettings netrcSettings) passSettings) podmanSettings) hostNetworkSettings) noneNetworkSettings) namedNetworkSettings) containerNameSettings) hostnameSettings
      );

      # Special handling for lists - concatenate instead of replace
      finalMounts =
        (baseSettings.mounts or [ ])
        ++ (gpgSettings.mounts or [ ])
        ++ (netrcSettings.mounts or [ ])
        ++ (passSettings.mounts or [ ])
        ++ vsixMounts
        ++ firewallMounts;

      finalRunArgs =
        (baseSettings.runArgs or [ ])
        ++ (podmanSettings.runArgs or [ ])
        ++ (hostNetworkSettings.runArgs or [ ])
        ++ (noneNetworkSettings.runArgs or [ ])
        ++ (namedNetworkSettings.runArgs or [ ])
        ++ (containerNameSettings.runArgs or [ ])
        ++ (hostnameSettings.runArgs or [ ])
        ++ firewallRunArgs;

      finalContainerEnv =
        (baseSettings.containerEnv or { })
        // (podmanSettings.containerEnv or { })
        // (netrcSettings.containerEnv or { });

      finalRemoteEnv = (baseSettings.remoteEnv or { }) // (gpgSettings.remoteEnv or { });

      finalOnCreateCommand =
        netrcSettings.onCreateCommand or (
          if baseSettings ? onCreateCommand && baseSettings.onCreateCommand != null then
            baseSettings.onCreateCommand
          else
            ""
        );

      # When the firewall is enabled, install a targeted sudoers rule during
      # postCreateCommand so the firewall can still be re-applied on restart via
      # `sudo /run/devcontainer-firewall` even after the general sudo is removed.
      # /run/devcontainer-remove-sudo is also included so it can self-escalate on
      # subsequent container starts (after the general vscode sudo has been removed).
      finalPostCreateCommand =
        let
          firewallSudoersCmd =
            if firewallEnabled then
              "printf 'vscode ALL=(root) NOPASSWD: /run/devcontainer-firewall\nvscode ALL=(root) NOPASSWD: /run/devcontainer-remove-sudo\n' | sudo tee /etc/sudoers.d/devcontainer-firewall > /dev/null && sudo chmod 440 /etc/sudoers.d/devcontainer-firewall"
            else
              null;
          # VS Code terminals are non-login shells, so /etc/profile.d/ is not
          # sourced automatically. Append a line to /etc/bash.bashrc so that
          # the firewall refresh and fw-refresh alias are available in every
          # interactive bash session (login and non-login alike).
          firewallBashrcCmd =
            if firewallEnabled then
              "grep -qF 'devcontainer-firewall.sh' /etc/bash.bashrc || echo '. /etc/profile.d/devcontainer-firewall.sh' | sudo tee -a /etc/bash.bashrc > /dev/null"
            else
              null;
          parts = lib.filter (p: p != null && p != "") [
            (mergedSettings.postCreateCommand or null)
            firewallSudoersCmd
            firewallBashrcCmd
          ];
        in
        if parts != [ ] then lib.concatStringsSep " && " parts else null;

      # Concatenate all postStartCommand sources: user base, gpg-agent, firewall.
      # This also fixes the pre-existing issue where gpg-agent would overwrite the
      # user's own postStartCommand when both were set.
      finalPostStartCommand =
        let
          parts = lib.filter (p: p != null && p != "") [
            (baseSettings.postStartCommand or null)
            (gpgSettings.postStartCommand or null)
            (if firewallEnabled then "sudo /run/devcontainer-firewall" else null)
            (if firewallEnabled then "/run/devcontainer-remove-sudo" else null)
          ];
        in
        if parts != [ ] then lib.concatStringsSep " && " parts else null;

    in
    (lib.removeAttrs mergedSettings [
      "onCreateCommand"
      "postCreateCommand"
      "postStartCommand"
    ])
    // lib.optionalAttrs (finalPostStartCommand != null) {
      postStartCommand = finalPostStartCommand;
    }
    // lib.optionalAttrs (finalPostCreateCommand != null) {
      postCreateCommand = finalPostCreateCommand;
    }
    // {
      mounts = finalMounts;
      runArgs = finalRunArgs;
      containerEnv = finalContainerEnv;
      remoteEnv = finalRemoteEnv;
    }
    // lib.optionalAttrs (finalOnCreateCommand != null && finalOnCreateCommand != "") {
      onCreateCommand = finalOnCreateCommand;
    };

  devcontainerSettings =
    let
      # Get the default extensions and user extensions
      defaultExtensions = [ ];
      userExtensions = computedSettings.customizations.vscode.extensions or [ ];
      # Merge extensions: defaults + user extensions + vsix container paths, then remove vscodevim.vim
      allExtensions = lib.unique (defaultExtensions ++ userExtensions ++ vsixContainerPaths);
      filteredExtensions = lib.filter (ext: ext != "vscodevim.vim") allExtensions;

      # Then apply customizations that need special handling
      finalSettings = computedSettings // {
        customizations = computedSettings.customizations // {
          vscode =
            computedSettings.customizations.vscode
            // {
              extensions = filteredExtensions;
            }
            // lib.optionalAttrs (cfg.network.mode == "host" || cfg.network.mode == "none") {
              settings = computedSettings.customizations.vscode.settings or { } // {
                "remote.autoForwardPorts" = false;
              };
            };
        };
      };
    in
    finalSettings;
  file = settingsFormat.generate "devcontainer.json" devcontainerSettings;
  inherit (lib)
    types
    mkOption
    mkIf
    ;
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
          "pass"
          "cli"
        ]
      );
      default = [ ];
      description = "List of tweaks to apply to the devcontainer configuration. 'cli': installs the devcontainer CLI (@devcontainers/cli) on the host shell.";
    };

    vsix = lib.mkOption {
      type = lib.types.listOf (
        lib.types.either lib.types.str (
          lib.types.submodule {
            options.url = lib.mkOption { type = lib.types.str; };
            options.sha256 = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
          }
        )
      );
      default = [ ];
      description = ''
        List of .vsix extension files to fetch into the Nix store at build time
        and install into VS Code. Each entry can be a URL string or an attrset
        with "url" and "sha256" attributes.
      '';
    };

    network = import ./network.nix { inherit lib; };

    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of the devcontainer. Sets the container name via --name runArg.
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
          default = null;
          description = ''
            Command to run after the container is created.
          '';
        };

        options.customizations.vscode.extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
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
      ++ tweak-vscode.packages cfg
      ++ tweak-podman.packages cfg
      ++ tweak-cli.packages cfg;
    enterShell = ''
      cat ${file} > ${config.env.DEVENV_ROOT}/.devcontainer.json
    ''
    + tweak-podman.enterShell cfg;
  };
}
