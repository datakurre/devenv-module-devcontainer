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
    url: github:nixos/nixpkgs/nixos-25.05
profile: shell
```

**`devenv.nix`** — all config lives under `profiles.shell.module` so that the `devcontainer` profile activates independently without pulling in shell packages:

```nix
{ self, lib, ... }:
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
imports:
  - devenv-module-devcontainer
allowUnfree: true
```

**`devenv.local.nix`** — personal devcontainer configuration under `profiles.devcontainer.module`:

```nix
{
  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.tweaks = [ "podman" "vscode" "gpg-agent" ];
    devcontainer.networkMode = "host";
    devcontainer.settings.customizations.vscode.extensions = [
      "bbenoist.Nix"
      "GitHub.copilot"
      "GitHub.copilot-chat"
      "mkhl.direnv"
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
| `tweaks` | `rootless`, `podman`, `vscode`, `gpg-agent`, `netrc` | `rootless`: rootless Podman config; `podman`: Nix-provided Podman; `vscode`: Nix-provided VS Code; `gpg-agent`: bind-mounts host gpg-agent socket into container; `netrc`: mounts `.netrc` into container (requires `netrc` option) |
| `networkMode` | `bridge`, `host` | `host` shares the host network namespace |
| `netrc` | path | Path to `.netrc` file to mount. Required when using the `netrc` tweak |
| `settings` | any | Pass-through to `devcontainer.json` |

## License

See LICENSE file.
