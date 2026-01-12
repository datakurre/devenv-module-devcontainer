# devenv-module-devcontainer

A [devenv](https://devenv.sh) module that generates `.devcontainer.json` for VS Code with support also for rootless Podman, and a fully self-contained mode.

## Installation

Add to your `devenv.yaml`:

```yaml
inputs:
  devenv-module-devcontainer:
    url: git+https://.../devenv-module-devcontainer
    flake: false
imports:
  - devenv-module-devcontainer
```

## Configuration

Enable and configure in `devenv.nix`:

```nix
{ pkgs, ... }:
{
  devcontainer.enable = true;
  devcontainer.mode = "podman";  # "default" (default), "podman", or "self-contained"
  devcontainer.networkMode = "host";  # "bridge" (default) or "host"
  devcontainer.settings.customizations.vscode.extensions = [
    "mkhl.direnv"
    "bbenoist.Nix"
    "vscodevim.vim"
  ];
}
```

### Modes

| Mode | Description |
|------|-------------|
| `default` | Creates minimal devcontainer.json |
| `podman` | Creates rootless Podman compatible devcontainer.json |
| `self-contained` | Provides rootless Podman + VS Code via Nix |

With **podman**, configure VS Code:
```json
{
  "dev.containers.dockerPath": "podman",
  "dev.containers.dockerSocketPath": "/var/run/user/1000/podman/podman.sock"
}
```

### Network Mode

| Value | Effect |
|-------|--------|
| `bridge` | Default container networking |
| `host` | Shares host network namespace—useful for accessing host services without port forwarding |

### Settings

Pass any valid devcontainer.json options via `devcontainer.settings`:

```nix
{
  devcontainer.settings = {
    image = "ghcr.io/cachix/devenv/devcontainer:latest";
    updateContentCommand = "devenv shell -- echo Ready.";
  };
}
```

## Profiles

Use [devenv profiles](https://devenv.sh/reference/options/#profiles) for user-specific configurations:

```nix
{
  # Shared project settings
  devcontainer.networkMode = "host";
  devcontainer.settings.customizations.vscode.extensions = [
    "bbenoist.Nix"
    "mkhl.direnv"
  ];

  # User-specific profile
  profiles.myprofile.module = {
    devcontainer.enable = true;
    devcontainer.mode = "self-contained";
    devcontainer.settings.customizations.vscode.extensions = [
      "vscodevim.vim"
    ];
  };
}
```

Activate with `devenv --profile myprofile shell` or `DEVENV_PROFILE=myprofile devenv shell`.

Alternatively, use `devenv.local.nix` for uncommitted personal settings.

## Usage

```bash
devenv shell  # Generates .devcontainer.json
```

Then use VS Code's **"Reopen in Container"** command.

## License

See LICENSE file.