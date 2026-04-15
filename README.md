# devenv-module-devcontainer

A [devenv](https://devenv.sh) module that generates `.devcontainer.json` for VS Code with support for rootless Podman and a fully self-contained mode.

## Recommended Usage Pattern

The recommended way to use this module keeps devcontainer tooling (VS Code, Podman) out of the default developer shell by using devenv [profiles](https://devenv.sh/reference/options/#profiles) and local override files.

### Project files (committed)

**`devenv.yaml`** — defines the default `shell` profile without the devcontainer module:

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:nixos/nixpkgs/nixos
profile: shell
```

**`devenv.nix`** — all config lives under `profiles.shell.module` so that the `devcontainer` profile activates independently without pulling in shell packages:

```nix
let
  shell = { pkgs, ... }: {
    packages = [ pkgs.gnumake ];
    dotenv.enable = true;
  };
in
{
  profiles.shell.module = {
    imports = [ shell ];
  };
}
```

**`Makefile`** — bootstraps local files from examples and launches VS Code via the devcontainer profile:

```makefile
.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: shell
shell: ## Enter devenv shell
	devenv shell

.PHONY: develop
develop: devenv.local.nix devenv.local.yaml ## Bootstrap opinionated development environment
	devenv shell --profile=devcontainer -- code .

devenv.local.nix:
	cp devenv.local.nix.example devenv.local.nix

devenv.local.yaml:
	cp devenv.local.yaml.example devenv.local.yaml
```

**`devenv.local.nix.example`** and **`devenv.local.yaml.example`** — committed templates that developers copy locally (gitignored actual files).

### Local files (gitignored)

**`devenv.local.yaml`** — adds this module as an input for developers who want devcontainer support:

```yaml
inputs:
  devenv-module-devcontainer:
    url: github:datakurre/devenv-module-devcontainer
    flake: false
  devenv-module-devcontainer-nixpkgs:
    url: github:nixos/nixpkgs
imports:
  - devenv-module-devcontainer
```

**`devenv.local.nix`** — personal devcontainer configuration under `profiles.devcontainer.module`:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "gpg-agent" ];
    devcontainer.settings.customizations.vscode.extensions = [
      "GitHub.copilot"
      "GitHub.copilot-chat"
      "datakurre.devenv"
      "jnoortheen.nix-ide"
      "vscodevim.vim"
    ];
  };
}
```

### Developer workflow

```bash
# First time: copies example files and opens VS Code with devcontainer profile
make develop

# Day-to-day: enter the regular shell (no devcontainer tooling)
make shell

# Inside the container: uses the default shell profile
devenv shell
```

`make develop` will:
1. Copy `devenv.local.nix.example` → `devenv.local.nix` if not present
2. Copy `devenv.local.yaml.example` → `devenv.local.yaml` if not present
3. Run `devenv shell --profile=devcontainer` (activates only the devcontainer profile)
4. Launch VS Code, which prompts to "Reopen in Container"

## Options

| Option | Values | Description |
|--------|--------|-------------|
| `enable` | `true`, `false` | Enable `.devcontainer.json` generation |
| `tweaks` | `rootless`, `podman`, `vscode`, `gpg-agent`, `netrc`, `pass`, `cli` | `rootless`: rootless Podman config; `podman`: Nix-provided Podman; `vscode`: Nix-provided VS Code; `gpg-agent`: bind-mounts host gpg-agent socket into container; `netrc`: mounts `.netrc` into container (requires `netrc` option); `pass`: mounts `$HOME/.password-store` into container; `cli`: installs the devcontainer CLI (`@devcontainers/cli`) on the host shell |
| `vsix` | list of URL strings or `{ url; sha256 }` attrsets | Fetch `.vsix` extension files into the Nix store at eval time and install them into the container's VS Code on creation. Each entry is either a plain URL string or an attrset with `url` and `sha256` keys. |
| `network.mode` | `bridge`, `host`, `none`, `named` | `bridge` (default): standard container networking; `host`: shares the host network namespace; `none`: disables all networking (complete isolation); `named`: joins the Docker/Podman network specified by `network.name` |
| `network.name` | string | Name of the Docker/Podman network to join. Required when `network.mode = "named"`. The network must be pre-created before starting the container (e.g. `docker network create my-net`). Two devcontainers using the same name share that network and can reach each other by container name. |
| `network.hostname` | string | Container hostname set via --hostname runArg. Optional. |
| `network.allowedHosts` | list of strings | Outbound allowlist: hostnames, bare IPs, or CIDR ranges the container may reach. When non-empty, all other outbound traffic is blocked via nftables. Compatible with `network.mode = "bridge"` or `"named"`. Loopback and DNS are always allowed. Inbound traffic is not filtered. |
| `network.allowedServices` | list of strings | Service shortcuts that expand to curated host allowlists. Available: `azure`, `claude`, `dockerhub`, `elm`, `github`, `gitlab`, `go`, `google`, `haskell`, `java`, `lua`, `nix`, `javascript`, `openai`, `python`. Merged with `network.allowedHosts`. Inbound traffic is not filtered. |
| `netrc` | path | Path to `.netrc` file to mount. Required when using the `netrc` tweak |
| `settings` | any | Pass-through to `devcontainer.json` |

## Network sandboxing

This module is often used in multi-project environments where different projects (or the same project at different stages) need different sandbox levels — in particular to control what LLM coding agents can reach from inside the container.

Two independent controls are provided:

| Goal | Setting |
|------|---------|
| Restrict outbound to a specific allowlist | `network.allowedHosts` and/or `network.allowedServices` |
| Block all networking completely | `network.mode = "none"` |

### `network.allowedHosts` and `network.allowedServices` — outbound allowlist

When the combined allowlist (`allowedHosts` + enabled `allowedServices`) is non-empty the module:

1. Generates a shell script (stored in the Nix store) that programs nftables OUTPUT rules.
2. Bind-mounts the script into the container at `/run/devcontainer-firewall`.
3. Adds `--cap-add=NET_ADMIN` to `runArgs` so the container can modify its own network namespace.
4. Calls `sudo /run/devcontainer-firewall` from `postStartCommand` so the rules are applied at every container start.

The default OUTPUT policy is **DROP**. The following are always permitted regardless of the list:

- Loopback (`lo` interface)
- DNS queries (UDP/TCP port 53) so hostname resolution keeps working
- Already-established / related connections

Each entry in `allowedHosts` can be:
- a **hostname** (e.g. `"github.com"`) — resolved via `getent` at container start; all returned IPs are individually allowed
- a bare **IP address** (e.g. `"192.168.1.10"`)
- a **CIDR range** (e.g. `"10.0.0.0/8"`, `"2001:db8::/32"`)

`allowedServices` is a convenience shortcut for known services. Example:

```nix
devcontainer.network.allowedServices = [ "github" "openai" ];
```

This expands to a maintained set of hostnames for each named service. The result is merged with `allowedHosts`.

IPv4 and IPv6 are handled separately. If `nft` is absent in the container image, the firewall script automatically re-executes itself inside `nix shell nixpkgs#nftables` to obtain it.

Only outbound traffic is filtered (OUTPUT hook). Inbound traffic is not filtered by this firewall, so published/forwarded devcontainer service ports remain reachable.

`allowedHosts`/`allowedServices` works with `network.mode = "bridge"` (the default) or `"named"`; combining either with `"host"` or `"none"` is caught at eval time with a clear error.

### Security hardening: sudo removal

After applying the firewall rules the script removes `/etc/sudoers.d/vscode`, revoking the container user's passwordless `sudo`. Without this the user could trivially flush the rules (`sudo iptables -F OUTPUT`). With it removed:

- The user cannot call `iptables` directly (requires `CAP_NET_ADMIN`, which is only available to root)
- The user cannot escalate to root (no `sudo` or `su` without a password)
- The firewall rules persist for the container's lifetime

### `network.mode = "none"` — complete isolation

Sets `--network=none` on the container. No network interfaces are created at all. Use this for the strictest possible sandbox where no network access is needed.

### Per-project and per-developer flexibility

Because `devenv.local.nix` is gitignored, each developer can choose their own sandbox level independently of the project default. A typical pattern:

**Project `devenv.nix`** (committed) — defines a recommended allowlist under the devcontainer profile:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "cli" ];
    devcontainer.network.allowedHosts = [
      "api.openai.com"        # LLM API
      "cache.nixos.org"       # Nix binary cache
      "github.com"            # source control
    ];
    devcontainer.settings.customizations.vscode.extensions = [
      "GitHub.copilot"
      "GitHub.copilot-chat"
      "jnoortheen.nix-ide"
    ];
  };
}
```

**Developer `devenv.local.nix`** (gitignored) — a developer who needs stricter isolation overrides the list (or uses `none`):

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "cli" ];
    # Tighter sandbox: only the Nix cache and GitHub, no LLM API
    devcontainer.network.allowedHosts = [
      "cache.nixos.org"
      "github.com"
    ];
  };
}
```

Or a developer doing offline-only work:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" ];
    devcontainer.network.mode = "none";
  };
}
```

### `network.mode = "named"` — shared named network

Sets `--network=<name>` on the container, joining a pre-existing Docker/Podman network by name. Two devcontainers using the same network name can communicate with each other.

```nix
devcontainer.network.mode = "named";
devcontainer.network.name = "my-project-net";
```

```bash
# Pre-create the shared network once (on the host):
docker network create my-project-net
```

The nftables firewall (`allowedHosts`/`allowedServices`) is compatible with named networks.

## License

See LICENSE file.
