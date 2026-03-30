#!/bin/sh
# Firewall setup for the allowed-hosts integration test fixture (nftables).
#
# Allowed outbound: github.com (resolved at runtime) + loopback + DNS.
# Everything else is blocked so the test can verify the allowlist behaviour.

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

ALLOWED_HOSTS="github.com"

# In dev mode, allow extra hosts to be injected at runtime without a rebuild:
#   sudo EXTRA_ALLOWED_HOSTS="pypi.org npmjs.com" /run/devcontainer-firewall
if [ -n "${EXTRA_ALLOWED_HOSTS:-}" ]; then
  ALLOWED_HOSTS="$ALLOWED_HOSTS $EXTRA_ALLOWED_HOSTS"
fi

echo "Applying devcontainer-firewall (test fixture — github.com allowed)..."

# Remove any previous incarnation of this table so the script is idempotent.
nft delete table inet devcontainer 2>/dev/null || true

# Build the base ruleset in our own named table.
nft add table inet devcontainer
nft add chain inet devcontainer output \
  '{ type filter hook output priority 0; policy drop; }'
# Loopback always allowed.
nft add rule inet devcontainer output oif lo accept
# DNS (port 53) so hostname resolution works.
nft add rule inet devcontainer output udp dport 53 accept
nft add rule inet devcontainer output tcp dport 53 accept
# Already-established connections (e.g. replies to inbound).
nft add rule inet devcontainer output ct state established,related accept

# Named sets for allowed addresses.
nft add set inet devcontainer allowed4 '{ type ipv4_addr; flags interval; }'
nft add set inet devcontainer allowed6 '{ type ipv6_addr; flags interval; }'
nft add rule inet devcontainer output ip  daddr @allowed4 accept
nft add rule inet devcontainer output ip6 daddr @allowed6 accept

# Resolve each allowed hostname and populate the sets.
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

echo "Firewall ready."

# Re-resolve hostnames periodically so rotating IPs stay reachable.
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
  disown
  echo "DNS refresh loop started (every 300s)."
fi

# Remove passwordless sudo so the container user cannot modify the rules.
# Skipped in dev mode (FIREWALL_DEV=1) to allow manual rule tweaking.
if [ "${FIREWALL_DEV:-0}" != "1" ]; then
  if [ -f /etc/sudoers.d/vscode ]; then
    rm -f /etc/sudoers.d/vscode
    echo "Passwordless sudo removed."
  fi
else
  echo "Dev mode: passwordless sudo kept. Re-run with EXTRA_ALLOWED_HOSTS to add hosts."
fi
