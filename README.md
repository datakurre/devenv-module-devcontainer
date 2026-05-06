# devenv-module-devcontainer

A [devenv](https://devenv.sh) module that generates `.devcontainer.json` for VS Code with support for rootless Podman and a fully self-contained mode.

## Quickstart

Run the interactive wizard in your project directory:

```bash
nix run https://github.com/datakurre/devenv-module-devcontainer.git
```

The wizard asks a few questions and writes four files:

| File | Description |
|------|-------------|
| `devenv.yaml` | Minimal devenv config (sets the default profile to `shell`) |
| `devenv.nix` | Stub shell module — add your packages and settings here |
| `devenv.local.yaml` | Adds this module as a devenv input (gitignored) |
| `devenv.local.nix` | Your personal devcontainer config (gitignored) |

After the wizard finishes:

```bash
# Activate the devcontainer profile and open VS Code — it will prompt "Reopen in Container"
devenv shell --profile=devcontainer -- code .
```

### Wizard steps

1. **Module URL** — the `devenv.local.yaml` input URL for this module (pre-filled from the URL you ran `nix run` with).
2. **Tweaks** — optional integrations to enable (see [Tweaks](#tweaks)).
3. **netrc path** — shown only if the `netrc` tweak is selected.
4. **Network mode** — `bridge` (default), `named`, or `host`.
5. **Named network details** — shown only when `named` is selected: network name and container hostname.
6. **VS Code extensions** — multi-select from a curated list; AI, language, and editor extensions. Network `allowedServices` are derived automatically from the selected AI/language extensions.
7. **Confirm** — shows a summary before writing any files.

## Usage pattern

The wizard follows the recommended pattern of keeping devcontainer tooling out of the default shell by using devenv [profiles](https://devenv.sh/reference/options/#profiles):

- `devenv.yaml` / `devenv.nix` are **committed** to the repository and define the `shell` profile used by all developers.
- `devenv.local.yaml` / `devenv.local.nix` are **gitignored** and hold each developer's personal devcontainer configuration.

**`devenv.yaml`** (committed):

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:nixos/nixpkgs/nixos
profile: shell
```

**`devenv.nix`** (committed):

```nix
{
  profiles.shell.module = { pkgs, ... }: {
    packages = [ pkgs.gnumake ];
  };
}
```

**`devenv.local.yaml`** (gitignored):

```yaml
inputs:
  devenv-module-devcontainer:
    url: git+https://github.com/datakurre/devenv-module-devcontainer
    flake: false
  devenv-module-devcontainer-nixpkgs:
    url: github:nixos/nixpkgs
imports:
  - devenv-module-devcontainer
```

**`devenv.local.nix`** (gitignored):

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
    ];
  };
}
```

## Tweaks

| Tweak | Description |
|-------|-------------|
| `podman` | Nix-provided rootless Podman; sets `containerUser`, `HOME`, and `--userns=keep-id` |
| `vscode` | Nix-provided VS Code on the host shell |
| `gpg-agent` | Bind-mounts the host GPG agent socket into the container |
| `netrc` | Mounts a `.netrc` file into the container (requires the `netrc` option) |
| `devcontainer` | Installs the `@devcontainers/cli` on the host shell |

## Options

| Option | Values | Description |
|--------|--------|-------------|
| `enable` | `true`, `false` | Enable `.devcontainer.json` generation |
| `tweaks` | see [Tweaks](#tweaks) | List of tweaks to enable |
| `vsix` | list of URL strings or `{ url; sha256 }` attrsets | Fetch `.vsix` extension files into the Nix store at eval time and install them on container creation |
| `network.mode` | `bridge`, `host`, `named` | `bridge` (default): standard container networking; `host`: shares the host network namespace; `named`: joins the Docker/Podman network specified by `network.name` |
| `network.name` | string | Name of the Docker/Podman network to join when `network.mode = "named"`. Must be pre-created on the host. |
| `network.hostname` | string | Container hostname set via `--hostname`. Optional. |
| `network.allowedHosts` | list of strings | Outbound allowlist: hostnames, bare IPs, or CIDR ranges the container may reach. All other outbound traffic is blocked via nftables. Loopback and DNS are always allowed. |
| `network.allowedServices` | list of strings | Service shortcuts that expand to curated host allowlists. Available: `azure`, `claude`, `dockerhub`, `elm`, `github`, `gitlab`, `go`, `google`, `haskell`, `java`, `javascript`, `lua`, `nix`, `openai`, `python`. Merged with `allowedHosts`. |
| `netrc` | path | Path to the `.netrc` file to mount. Required when using the `netrc` tweak. |
| `settings` | any | Pass-through to `devcontainer.json` |

## Network sandboxing

This module is often used in environments where LLM coding agents run inside containers and network access needs to be controlled per-project or per-developer.

Two independent controls are provided:

| Goal | Setting |
|------|---------|
| Restrict outbound to a specific allowlist | `network.allowedHosts` and/or `network.allowedServices` |
| Block all networking completely | `network.mode = "named"` with an isolated network, or `--network=none` via `settings.runArgs` |

### `network.allowedHosts` and `network.allowedServices` — outbound allowlist

When the combined allowlist (`allowedHosts` + enabled `allowedServices`) is non-empty the module:

1. Generates a shell script (stored in the Nix store) that programs nftables OUTPUT rules.
2. Bind-mounts the script into the container at `/run/devcontainer-firewall`.
3. Adds `--cap-add=NET_ADMIN` to `runArgs` so the container can modify its own network namespace.
4. Calls `sudo /run/devcontainer-firewall` from `postStartCommand` so the rules are applied at every container start.

The default OUTPUT policy is **DROP**. The following are always permitted:

- Loopback (`lo` interface)
- DNS queries (UDP/TCP port 53)
- Already-established / related connections

Each entry in `allowedHosts` can be a hostname, a bare IP, or a CIDR range. Hostnames are resolved via `getent` at container start and all returned IPs are individually allowed.

`allowedServices` is a convenience shortcut for known services:

```nix
devcontainer.network.allowedServices = [ "github" "openai" ];
```

If `nft` is absent in the container image, the firewall script re-executes itself inside `nix shell nixpkgs#nftables` automatically.

Only outbound traffic is filtered (OUTPUT hook). Inbound traffic is not filtered, so published devcontainer service ports remain reachable.

#### Security hardening: sudo removal

After applying the firewall rules the script removes `/etc/sudoers.d/vscode`, revoking the container user's passwordless `sudo`. Without this the user could trivially flush the rules (`sudo nft flush ruleset`). With it removed:

- The user cannot call `nft` directly (requires `CAP_NET_ADMIN`, which is only available to root)
- The user cannot escalate to root (no `sudo` or `su` without a password)
- The firewall rules persist for the container's lifetime

### Per-project and per-developer flexibility

Because `devenv.local.nix` is gitignored, each developer can choose their own sandbox level independently of the project default.

**Project `devenv.nix`** (committed) — defines a recommended allowlist under the devcontainer profile:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "devcontainer" ];
    devcontainer.network.allowedServices = [ "github" "nix" "openai" ];
    devcontainer.settings.customizations.vscode.extensions = [
      "GitHub.copilot"
      "GitHub.copilot-chat"
      "jnoortheen.nix-ide"
    ];
  };
}
```

**Developer `devenv.local.nix`** (gitignored) — tighter isolation:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "devcontainer" ];
    # Only Nix cache and GitHub, no LLM API
    devcontainer.network.allowedServices = [ "nix" "github" ];
  };
}
```

### `network.mode = "named"` — shared named network

Joins a pre-existing Docker/Podman network so that multiple devcontainers can communicate:

```nix
devcontainer.network.mode = "named";
devcontainer.network.name = "my-project-net";
```

```bash
# Pre-create the shared network once on the host:
docker network create my-project-net
```

The nftables firewall (`allowedHosts`/`allowedServices`) is compatible with named networks.

## License

See LICENSE file.
