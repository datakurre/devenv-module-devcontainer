#!/bin/sh
# Firewall setup for the allowed-hosts integration test fixture.
#
# Allowed outbound: github.com (resolved at runtime) + loopback + DNS.
# Everything else is blocked so the test can verify the allowlist behaviour.

# Self-escalate to root; the vscode user has passwordless sudo in devcontainer images.
if [ "$(id -u)" != "0" ]; then
  exec sudo "$0" "$@"
fi

# If iptables is not on PATH, re-exec inside a nix shell that provides it.
# This is safe here because the firewall hasn't been applied yet, so internet
# access (needed by `nix shell` to fetch iptables) is still unrestricted.
if ! command -v iptables >/dev/null 2>&1; then
  NIX_BIN="$(command -v nix 2>/dev/null || echo /nix/var/nix/profiles/default/bin/nix)"
  if [ -x "$NIX_BIN" ]; then
    exec "$NIX_BIN" shell nixpkgs#iptables --command sh "$0" "$@"
  fi
fi

ALLOWED_HOSTS="github.com"

# In dev mode, allow extra hosts to be injected at runtime without a rebuild:
#   EXTRA_ALLOWED_HOSTS="pypi.org npmjs.com" sudo /run/devcontainer-firewall
if [ -n "${EXTRA_ALLOWED_HOSTS:-}" ]; then
  ALLOWED_HOSTS="$ALLOWED_HOSTS $EXTRA_ALLOWED_HOSTS"
fi

setup_ipv4() {
  iptables -F OUTPUT
  iptables -P OUTPUT DROP
  # Loopback always allowed
  iptables -A OUTPUT -o lo -j ACCEPT
  # DNS (port 53) so hostname resolution works
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
  # Already-established connections (e.g. replies to inbound)
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  # Resolve each allowed hostname and add a per-IP rule
  for host in $ALLOWED_HOSTS; do
    for ip in $(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do
      iptables -A OUTPUT -d "$ip" -j ACCEPT
      echo "  ipv4 allowed: $host -> $ip"
    done
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
}

echo "Applying devcontainer-firewall (test fixture — github.com allowed)..."

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

echo "Firewall ready."

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
