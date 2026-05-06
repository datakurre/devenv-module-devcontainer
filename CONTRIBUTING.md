# Contributing

## Testing network sandboxing

### Prerequisites

- The `devcontainer` tweak must be active so the `devcontainer` CLI is on PATH.
- `podman` or `docker` must be available.

```nix
devcontainer.tweaks = [ "podman" "vscode" "devcontainer" ];
```

Re-enter the devcontainer shell after changing tweaks:

```bash
devenv shell --profile=devcontainer
```

### Running the test suite

```bash
./tests/test-allowed-hosts.sh          # run all checks, remove container on exit
./tests/test-allowed-hosts.sh --keep   # keep container running for manual inspection
./tests/test-allowed-hosts.sh --dev    # dev mode: skip sudo-removal tests, pass FIREWALL_DEV=1
./tests/test-allowed-hosts.sh --dev --keep
```

The test suite spins up the fixture at `tests/fixtures/allowed-hosts/` — a plain devcontainer that allows outbound traffic to `github.com` only — and verifies the following:

| Check | Expected |
|-------|----------|
| Loopback 127.0.0.1 reachable | pass |
| DNS: `getent hosts github.com` | pass — DNS port 53 always allowed |
| DNS: `getent hosts google.com` | pass — DNS resolution works even for blocked hosts |
| `curl https://github.com` | pass — explicitly in allowlist |
| `curl https://www.google.com` | **fail** — not in allowlist |
| `curl https://example.com` | **fail** — not in allowlist |
| `nc 1.1.1.1 443` (direct IP) | **fail** — not in allowlist |
| `curl https://api.openai.com` | **fail** — not in allowlist |
| `sudo true` | **fail** — passwordless sudo removed |
| `iptables -F OUTPUT` (with or without sudo) | **fail** — cannot flush rules |

### Manual inspection

After running with `--keep`:

```bash
# Open a shell in the running fixture container
devcontainer exec --workspace-folder tests/fixtures/allowed-hosts -- bash

# Inside: view the applied nftables rules
nix shell nixpkgs#nftables -- nft list table inet devcontainer
```
