{
  pkgs,
  lib,
  cfg,
}:
let
  # All curated service allowlist definitions: { name = { hosts; cidrs; }; }
  allServices = import ./services;

  # Detect CIDR notation: any string containing '/' followed by decimal digits.
  isCidr = s: builtins.match ".*/[0-9]+" s != null;

  enabledAllowedServices = cfg.network.allowedServices;

  allowedServiceHosts = lib.concatLists (
    map (name: allServices.${name}.hosts) enabledAllowedServices
  );

  allowedServiceCidrs = lib.concatLists (
    map (name: allServices.${name}.cidrs) enabledAllowedServices
  );

  userHosts = lib.filter (s: !isCidr s) cfg.network.allowedHosts;
  userCidrs = lib.filter isCidr cfg.network.allowedHosts;

  effectiveHosts = lib.unique (userHosts ++ allowedServiceHosts);
  effectiveCidrs = lib.unique (userCidrs ++ allowedServiceCidrs);

  firewallEnabled = effectiveHosts != [ ] || effectiveCidrs != [ ];

  # Generate nftables allowlist firewall script for network.allowedHosts and
  # network.allowedServices. The rules only hook OUTPUT so inbound traffic is
  # untouched and published devcontainer ports keep working.
  firewallScript =
    let
      hostsStr = lib.concatStringsSep " " effectiveHosts;
      cidrsStr = lib.concatStringsSep " " effectiveCidrs;
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
        echo "WARNING: nft not found and nix unavTetävailable — outbound traffic unrestricted"
        exit 0
      fi

      ALLOWED_HOSTS="${hostsStr}"
      ALLOWED_CIDRS="${cidrsStr}"

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

      # Named sets for allowed addresses — flags interval enables CIDR prefix support.
      # Using 2>/dev/null || true on element additions to silence harmless
      # "already exists / overlapping interval" errors for duplicate IPs.
      nft add set inet devcontainer allowed4 '{ type ipv4_addr; flags interval; }'
      nft add set inet devcontainer allowed6 '{ type ipv6_addr; flags interval; }'
      nft add rule inet devcontainer output ip  daddr @allowed4 accept
      nft add rule inet devcontainer output ip6 daddr @allowed6 accept

      # Add CIDR ranges first so that host IPs within a CIDR don't produce
      # "overlapping interval" errors that would silently prevent the broader
      # prefix from landing in the set.
      # Add CIDR ranges directly to the appropriate set.
      for cidr in $ALLOWED_CIDRS; do
        case "$cidr" in
          *:*) nft add element inet devcontainer allowed6 "{ $cidr }" 2>/dev/null || true; echo "  allowed: CIDR $cidr" ;;
          *)   nft add element inet devcontainer allowed4 "{ $cidr }" 2>/dev/null || true; echo "  allowed: CIDR $cidr" ;;
        esac
      done

      # Implicitly allow all nameservers listed in /etc/resolv.conf so that
      # DNS-over-TLS (port 853), DNS-over-HTTPS (port 443), and any other
      # non-standard resolver mechanism can still reach the configured
      # nameservers.  Plain port-53 traffic is already unconditionally
      # permitted above, but adding the IPs to the allowed sets covers every
      # port/protocol to those trusted hosts.
      if [ -f /etc/resolv.conf ]; then
        for ns in $(awk '/^nameserver[[:space:]]/ { print $2 }' /etc/resolv.conf); do
          case "$ns" in
            127.*|::1) ;;  # loopback already accepted via oif lo rule
            *:*) nft add element inet devcontainer allowed6 "{ $ns }" 2>/dev/null || true
                 echo "  allowed: nameserver $ns (resolv.conf)" ;;
            *)   nft add element inet devcontainer allowed4 "{ $ns }" 2>/dev/null || true
                 echo "  allowed: nameserver $ns (resolv.conf)" ;;
          esac
        done
      fi

      echo "Network allowlist applied."

      # Start a background loop to re-resolve hostnames periodically.
      # Cloud services rotate IPs on short DNS TTLs; without this, new IPs
      # returned after the initial resolution would be dropped by the firewall.
      if [ -n "$ALLOWED_HOSTS" ]; then
        (
          while true; do
            sleep 300
            for host in $ALLOWED_HOSTS; do
              for ip in $(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
                nft add element inet devcontainer allowed4 "{ $ip }" 2>/dev/null || true
              done
              for ip in $(getent ahostsv6 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
                nft add element inet devcontainer allowed6 "{ $ip }" 2>/dev/null || true
              done
            done
          done
        ) &
        echo "DNS refresh loop started (every 300s)."
      fi

    '';

  removeSudoScript = pkgs.writeScript "devcontainer-remove-sudo" ''
    #!/bin/sh
    if [ "$(id -u)" != "0" ]; then
      exec sudo "$0" "$@"
    fi
    if [ -f /etc/sudoers.d/vscode ]; then
      rm -f /etc/sudoers.d/vscode
      echo "Passwordless sudo removed."
    fi
  '';
in
{
  inherit
    firewallEnabled
    firewallScript
    removeSudoScript
    ;
}
