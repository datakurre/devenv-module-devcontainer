# devenv-module-devcontainer

A [devenv](https://devenv.sh) module that generates `.devcontainer.json` for VS Code with support for rootless Podman and a fully self-contained mode.

## Installation

Add to your `devenv.yaml`:

```yaml
inputs:
  devenv-module-devcontainer:
    url:  git+https://.../devenv-module-devcontainer
    flake: false
imports:
  - devenv-module-devcontainer
```

## Configuration

Enable in `devenv.nix`:

```nix
{ pkgs, ... }:
{
  devcontainer.enable = true;
  devcontainer.tweaks = [ "podman" "vscode" ];
  devcontainer.networkMode = "host";
  devcontainer.settings.customizations.vscode.extensions = [
    "mkhl.direnv"
    "bbenoist.Nix"
  ];
}
```

### Options

| Option | Values | Description |
|--------|--------|-------------|
| `tweaks` | `rootless`, `podman`, `vscode` | `rootless`: rootless Podman config; `podman`: Nix-provided Podman; `vscode`: Nix-provided VS Code |
| `networkMode` | `bridge`, `host` | `host` shares host network namespace |
| `settings` | any | Pass-through to devcontainer.json |

## Using Profiles to Isolate Devcontainer

Use [profiles](https://devenv.sh/reference/options/#profiles) to avoid building devcontainer tooling on the host:

**devenv.yaml**:
```yaml
inputs:
  devenv-module-devcontainer:
    url: git+https://.../devenv-module-devcontainer
    flake: false
imports:
  - devenv-module-devcontainer
profile: shell  # Default profile
```

**devenv.nix**:
```nix
{ pkgs, ... }:
let
  shell = { pkgs, ... }: {
    services.postgres.enable = true;
    packages = [ pkgs.nodejs ];
  };
in
{
  profiles.shell.module = {
    imports = [ shell ];
  };

  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.networkMode = "host";
    devcontainer.tweaks = [ "podman" "vscode" ];
    devcontainer.settings.customizations.vscode.extensions = [
      "mkhl.direnv"
      "bbenoist.Nix"
    ];
  };
}
```

### Workflow

```bash
# Generate .devcontainer.json (host, without building project shell)
devenv --profile devcontainer shell --impure -c true

# Open in VS Code: "Reopen in Container"

# Inside container (uses default shell profile)
devenv shell
```

## Local Customization

Use `devenv.local.nix` for personal settings:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.settings.customizations.vscode.extensions = [
      "vscodevim.vim"
    ];
  };
}
```

## License

See LICENSE file.
