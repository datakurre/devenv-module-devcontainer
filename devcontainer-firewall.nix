{
  pkgs,
  lib,
  cfg,
}:
let
  # Curated allowlist presets for common services.
  # Source for GitHub domains: https://api.github.com/meta
  # Note: keep this list to concrete hostnames because getent does not resolve
  # wildcard entries like *.githubusercontent.com.
  knownAllowedServices = {
    github = {
      hosts = [
        "github.com"
        "api.github.com"
        "objects.githubusercontent.com"
        "raw.githubusercontent.com"
        "githubusercontent.com"
        "codeload.github.com"
        "uploads.github.com"
      ];
      metaEndpoint = "https://api.github.com/meta";
    };
  };

  unknownAllowedServices =
    lib.filter
      (name: !(builtins.hasAttr name knownAllowedServices))
      (builtins.attrNames cfg.network.allowedServices);

  enabledAllowedServices =
    lib.filter
      (name: cfg.network.allowedServices.${name} or false)
      (builtins.attrNames knownAllowedServices);

  allowedServiceHosts =
    lib.concatLists
      (map (name: knownAllowedServices.${name}.hosts or [ ]) enabledAllowedServices);
  effectiveAllowedHosts = lib.unique (cfg.network.allowedHosts ++ allowedServiceHosts);
  firewallEnabled = effectiveAllowedHosts != [ ];

  # Generate nftables allowlist firewall script for network.allowedHosts and
  # network.allowedServices. The rules only hook OUTPUT so inbound traffic is
  # untouched and published devcontainer ports keep working.
  firewallScript =
    let
      isCidr = s: builtins.match ".*/.*" s != null;
      hosts = lib.filter (s: !isCidr s) effectiveAllowedHosts;
      cidrs = lib.filter isCidr effectiveAllowedHosts;
      hostsStr = lib.concatStringsSep " " hosts;
      cidrsStr = lib.concatStringsSep " " cidrs;
      enabledServicesStr = lib.concatStringsSep " " enabledAllowedServices;
      githubMetaEndpoint = knownAllowedServices.github.metaEndpoint;
    in
    pkgs.writeScript "devcontainer-firewall" ''
      #!/bin/sh
      # Devcontainer outbound network allowlist (nftables).
      # Self-escalate to root; the vscode user has passwordless sudo in devcontainer images.
      if [ "$(id -u)" != "0" ]; then
        exec sudo "$0" "$@"
      fi

      # If nft is not on PATH, re-exec inside a nix shell that provides it.
      # This is safe here because the firewall hasn't been applied yet, so internet
      # access (needed by `nix shell` to fetch nftables) is still unrestricted.
      if ! command -v nft >/dev/null 2>&1; then
        NIX_BIN="$(command -v nix 2>/dev/null || echo /nix/var/nix/profiles/default/bin/nix)"
        if [ -x "$NIX_BIN" ]; then
          exec "$NIX_BIN" shell nixpkgs#nftables --command sh "$0" "$@"
        fi
        echo "WARNING: nft not found and nix unavailable — outbound traffic unrestricted"
        exit 0
      fi

      ALLOWED_HOSTS="${hostsStr}"
      ALLOWED_CIDRS="${cidrsStr}"
      ENABLED_SERVICES="${enabledServicesStr}"

      fetch_github_meta_cidrs() {
        if ! command -v curl >/dev/null 2>&1; then
          echo "WARNING: curl not found, skipping GitHub master-data CIDRs"
          return 0
        fi

        meta_json="$(curl -fsSL --retry 2 --connect-timeout 5 "${githubMetaEndpoint}" 2>/dev/null || true)"
        if [ -z "$meta_json" ]; then
          echo "WARNING: failed to fetch GitHub meta endpoint, continuing with static host allowlist"
          return 0
        fi

        # Extract IPv4 and IPv6 CIDRs from JSON without requiring jq.
        echo "$meta_json" \
          | grep -Eo '"([0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]+|[0-9a-fA-F:]+/[0-9]+)"' \
          | tr -d '"' \
          | sort -u \
          | tr '\n' ' '
      }

      if echo " $ENABLED_SERVICES " | grep -q " github "; then
        GITHUB_META_CIDRS="$(fetch_github_meta_cidrs)"
        if [ -n "$GITHUB_META_CIDRS" ]; then
          ALLOWED_CIDRS="$ALLOWED_CIDRS $GITHUB_META_CIDRS"
          echo "Loaded GitHub CIDR master data from ${githubMetaEndpoint}"
        fi
      fi

      # In dev mode, allow extra hosts to be injected at runtime without a rebuild:
      #   sudo EXTRA_ALLOWED_HOSTS="pypi.org npmjs.com" /run/devcontainer-firewall
      if [ -n "''${EXTRA_ALLOWED_HOSTS:-}" ]; then
        ALLOWED_HOSTS="$ALLOWED_HOSTS ''${EXTRA_ALLOWED_HOSTS}"
      fi

      echo "Applying devcontainer network allowlist..."

      # Remove any previous incarnation of this table so the script is idempotent.
      nft delete table inet devcontainer 2>/dev/null || true

      # Build the base ruleset: own named table so we never touch other tables.
      nft add table inet devcontainer
      # OUTPUT-only hook: outbound is sandboxed, inbound remains runtime default.
      nft add chain inet devcontainer output \
        '{ type filter hook output priority 0; policy drop; }'
      # Loopback always allowed.
      nft add rule inet devcontainer output oif lo accept
      # DNS so hostname resolution works.
      nft add rule inet devcontainer output udp dport 53 accept
      nft add rule inet devcontainer output tcp dport 53 accept
      # Already-established / related connections (e.g. replies to inbound).
      nft add rule inet devcontainer output ct state established,related accept

      # Named sets for allowed addresses — kernel uses a hash, not a linear scan.
      nft add set inet devcontainer allowed4 '{ type ipv4_addr; }'
      nft add set inet devcontainer allowed6 '{ type ipv6_addr; }'
      nft add rule inet devcontainer output ip  daddr @allowed4 accept
      nft add rule inet devcontainer output ip6 daddr @allowed6 accept

      # Resolve each hostname and populate the sets.
      for host in $ALLOWED_HOSTS; do
        for ip in $(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
          nft add element inet devcontainer allowed4 "{ $ip }"
          echo "  allowed: $host -> $ip"
        done
        for ip in $(getent ahostsv6 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
          nft add element inet devcontainer allowed6 "{ $ip }"
          echo "  allowed: $host -> $ip"
        done
      done

      # Add CIDR ranges directly to the appropriate set.
      for cidr in $ALLOWED_CIDRS; do
        case "$cidr" in
          *:*) nft add element inet devcontainer allowed6 "{ $cidr }"; echo "  allowed: CIDR $cidr" ;;
          *)   nft add element inet devcontainer allowed4 "{ $cidr }"; echo "  allowed: CIDR $cidr" ;;
        esac
      done

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
in
{
  inherit
    knownAllowedServices
    unknownAllowedServices
    enabledAllowedServices
    allowedServiceHosts
    effectiveAllowedHosts
    firewallEnabled
    firewallScript
    ;
}
