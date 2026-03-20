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
  cfg = config.devcontainer;
  settingsFormat = pkgs.formats.json { };

  # Fetch each vsix into the Nix store at build time
  vsixFetched = map
    (entry:
      let
        url = if builtins.isAttrs entry then entry.url else entry;
        sha256 = if builtins.isAttrs entry && entry ? sha256 then entry.sha256 else null;
        fetched = if sha256 != null
          then builtins.fetchurl { inherit url sha256; }
          else builtins.fetchurl url;
        filename = lib.last (lib.splitString "/" url);
      in {
        storePath = fetched;
        containerPath = "/run/host-vsix/${filename}";
        mount = "source=${fetched},target=/run/host-vsix/${filename},type=bind,readonly";
      }
    )
    cfg.vsix;

  vsixMounts = map (e: e.mount) vsixFetched;
  vsixContainerPaths = map (e: e.containerPath) vsixFetched;

  # Generate iptables/ip6tables allowlist firewall script for network.allowedHosts.
  # Stored in the Nix store on the host and bind-mounted into the container at
  # /run/devcontainer-firewall via the mounts list (see computedSettings below).
  firewallScript =
    let
      isCidr = s: builtins.match ".*/.*" s != null;
      hosts = lib.filter (s: !isCidr s) cfg.network.allowedHosts;
      cidrs = lib.filter isCidr cfg.network.allowedHosts;
      hostsStr = lib.concatStringsSep " " hosts;
      cidrsStr = lib.concatStringsSep " " cidrs;
    in
    pkgs.writeScript "devcontainer-firewall" ''
      #!/bin/sh
      # Devcontainer outbound network allowlist.
      # Self-escalate to root; the vscode user has passwordless sudo in devcontainer images.
      if [ "$(id -u)" != "0" ]; then
        exec sudo "$0" "$@"
      fi

      ALLOWED_HOSTS="${hostsStr}"
      ALLOWED_CIDRS="${cidrsStr}"

      # In dev mode, allow extra hosts to be injected at runtime without a rebuild:
      #   EXTRA_ALLOWED_HOSTS="pypi.org npmjs.com" sudo /run/devcontainer-firewall
      if [ -n "''${EXTRA_ALLOWED_HOSTS:-}" ]; then
        ALLOWED_HOSTS="$ALLOWED_HOSTS ''${EXTRA_ALLOWED_HOSTS}"
      fi
      setup_ipv4() {
        iptables -F OUTPUT
        iptables -P OUTPUT DROP
        iptables -A OUTPUT -o lo -j ACCEPT
        iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        for host in $ALLOWED_HOSTS; do
          for ip in $(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
            iptables -A OUTPUT -d "$ip" -j ACCEPT
            echo "  ipv4 allowed: $host -> $ip"
          done
        done
        for cidr in $ALLOWED_CIDRS; do
          case "$cidr" in
            *:*) ;;
            *) iptables -A OUTPUT -d "$cidr" -j ACCEPT; echo "  ipv4 allowed: CIDR $cidr" ;;
          esac
        done
      }

      setup_ipv6() {
        ip6tables -F OUTPUT
        ip6tables -P OUTPUT DROP
        ip6tables -A OUTPUT -o lo -j ACCEPT
        ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT
        ip6tables -A OUTPUT -p tcp --dport 53 -j ACCEPT
        ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        for host in $ALLOWED_HOSTS; do
          for ip in $(getent ahostsv6 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
            ip6tables -A OUTPUT -d "$ip" -j ACCEPT
            echo "  ipv6 allowed: $host -> $ip"
          done
        done
        for cidr in $ALLOWED_CIDRS; do
          case "$cidr" in
            *:*) ip6tables -A OUTPUT -d "$cidr" -j ACCEPT; echo "  ipv6 allowed: CIDR $cidr" ;;
          esac
        done
      }

      echo "Applying devcontainer network allowlist..."
      if command -v iptables >/dev/null 2>&1; then
        setup_ipv4
        echo "IPv4 rules applied."
      else
        echo "WARNING: iptables not found, IPv4 traffic unrestricted"
      fi
      if command -v ip6tables >/dev/null 2>&1; then
        setup_ipv6
        echo "IPv6 rules applied."
      else
        echo "WARNING: ip6tables not found, IPv6 traffic unrestricted"
      fi
      echo "Network allowlist applied."

      # Remove passwordless sudo so the container user cannot modify the rules.
      # Skipped in dev mode to allow manual rule tweaking.
      ${lib.optionalString (!cfg.network.dev) ''
        if [ -f /etc/sudoers.d/vscode ]; then
          rm -f /etc/sudoers.d/vscode
          echo "Passwordless sudo removed."
        fi
      ''}
      ${lib.optionalString cfg.network.dev ''
        echo "Dev mode: passwordless sudo kept. Re-run with EXTRA_ALLOWED_HOSTS to add hosts."
      ''}
    '';

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

      # Apply pass tweak
      passSettings = lib.optionalAttrs (lib.elem "pass" cfg.tweaks) {
        mounts = [
          "source=\${localEnv:HOME}/.password-store,target=/home/vscode/.password-store,type=bind,readonly"
        ];
      };

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

      # Apply network=none mode (complete network isolation)
      noneNetworkSettings = lib.optionalAttrs (cfg.networkMode == "none") {
        runArgs = [ "--network=none" ];
      };

      # allowedHosts: bind-mount the generated firewall script and request NET_ADMIN
      firewallMounts =
        if cfg.network.allowedHosts != [] && cfg.networkMode != "bridge"
        then throw "devcontainer.network.allowedHosts requires networkMode = \"bridge\""
        else lib.optional (cfg.network.allowedHosts != [])
          "source=${firewallScript},target=/run/devcontainer-firewall,type=bind,readonly";

      firewallRunArgs = lib.optional (cfg.network.allowedHosts != []) "--cap-add=NET_ADMIN";

      # Merge all settings with proper list concatenation and attrset merging
      mergedSettings = lib.recursiveUpdate baseSettings (
        lib.recursiveUpdate (
          lib.recursiveUpdate (
            lib.recursiveUpdate (
              lib.recursiveUpdate (
                lib.recursiveUpdate gpgSettings netrcSettings
              ) passSettings
            ) podmanSettings
          ) hostNetworkSettings
        ) noneNetworkSettings
      );

      # Special handling for lists - concatenate instead of replace
      finalMounts = (baseSettings.mounts or [])
        ++ (gpgSettings.mounts or [])
        ++ (netrcSettings.mounts or [])
        ++ (passSettings.mounts or [])
        ++ vsixMounts
        ++ firewallMounts;

      finalRunArgs = (baseSettings.runArgs or [])
        ++ (podmanSettings.runArgs or [])
        ++ (hostNetworkSettings.runArgs or [])
        ++ (noneNetworkSettings.runArgs or [])
        ++ firewallRunArgs;

      finalContainerEnv = (baseSettings.containerEnv or {})
        // (podmanSettings.containerEnv or {})
        // (netrcSettings.containerEnv or {});

      finalRemoteEnv = (baseSettings.remoteEnv or {})
        // (gpgSettings.remoteEnv or {});

      finalOnCreateCommand = netrcSettings.onCreateCommand or (if baseSettings ? onCreateCommand && baseSettings.onCreateCommand != null then baseSettings.onCreateCommand else "");

      # Concatenate all postStartCommand sources: user base, gpg-agent, firewall.
      # This also fixes the pre-existing issue where gpg-agent would overwrite the
      # user's own postStartCommand when both were set.
      finalPostStartCommand =
        let
          parts = lib.filter (p: p != null && p != "") [
            (baseSettings.postStartCommand or null)
            (gpgSettings.postStartCommand or null)
          (if cfg.network.allowedHosts != [] then
            (if cfg.network.dev then "FIREWALL_DEV=1 sudo /run/devcontainer-firewall"
             else "sudo /run/devcontainer-firewall")
          else null)
          ];
        in
        if parts != [] then lib.concatStringsSep " && " parts else null;

    in
      (lib.removeAttrs mergedSettings [ "onCreateCommand" "postCreateCommand" "postStartCommand" ])
      // lib.optionalAttrs (finalPostStartCommand != null) {
        postStartCommand = finalPostStartCommand;
      }
      // lib.optionalAttrs (mergedSettings.postCreateCommand or null != null) {
        postCreateCommand = mergedSettings.postCreateCommand;
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
      defaultExtensions = [];
      userExtensions = computedSettings.customizations.vscode.extensions or [ ];
      # Merge extensions: defaults + user extensions + vsix container paths, then remove vscodevim.vim
      allExtensions = lib.unique (defaultExtensions ++ userExtensions ++ vsixContainerPaths);
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
              // lib.optionalAttrs (cfg.networkMode == "host" || cfg.networkMode == "none") {
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
          "pass"
          "cli"
        ]
      );
      default = [ ];
      description = "List of tweaks to apply to the devcontainer configuration. 'cli': installs the devcontainer CLI (@devcontainers/cli) on the host shell.";
    };

    vsix = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options.url = lib.mkOption { type = lib.types.str; };
        options.sha256 = lib.mkOption { type = lib.types.str; default = ""; };
      }));
      default = [ ];
      description = ''
        List of .vsix extension files to fetch into the Nix store at build time
        and install into VS Code. Each entry can be a URL string or an attrset
        with "url" and "sha256" attributes.
      '';
    };

    networkMode = lib.mkOption {
      type = lib.types.enum [
        "bridge"
        "host"
        "none"
      ];
      default = "bridge";
      description = ''
        Network mode for the container.
        - "bridge": Use default network mode
        - "host": Use host networking (shares the host's network namespace)
        - "none": Disable all networking (complete isolation)
      '';
    };

    network = {
      allowedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          List of hostnames, IP addresses, or CIDR ranges the container is
          allowed to connect to outbound. When non-empty, all other outbound
          connections are blocked via iptables/ip6tables inside the container.

          Requires networkMode = "bridge". Each entry is either:
          - a hostname (e.g. "github.com") — resolved at container start via getent
          - a bare IP address (e.g. "192.168.1.10")
          - a CIDR range (e.g. "10.0.0.0/8", "2001:db8::/32")

          Loopback, DNS (port 53), and already-established connections are
          always permitted regardless of this list.

          Adds --cap-add=NET_ADMIN to runArgs automatically.
        '';
      };

      dev = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable dev mode for the network allowlist firewall.
          When true:
          - Passwordless sudo is NOT removed after the firewall is applied,
            so you can re-run the script manually to tweak rules.
          - The firewall script respects the EXTRA_ALLOWED_HOSTS environment
            variable, letting you add hosts at runtime without a Nix rebuild:
              EXTRA_ALLOWED_HOSTS="pypi.org npmjs.com" sudo /run/devcontainer-firewall
          Only meaningful when allowedHosts is non-empty.
        '';
      };
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
            "jnoortheen.nix-ide"
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
        (pkgs-devcontainer.vscode-with-extensions.override {
          vscode = pkgs-devcontainer.vscode;
          vscodeExtensions =
            [
              pkgs-devcontainer.vscode-extensions.ms-vscode-remote.remote-containers
            ]
            ++ optionals (lib.elem "vscodevim.vim" cfg.settings.customizations.vscode.extensions) [
              pkgs-devcontainer.vscode-extensions.vscodevim.vim
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
      ])
      ++ (optionals (lib.elem "cli" cfg.tweaks) [
        pkgs-devcontainer.devcontainer
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
