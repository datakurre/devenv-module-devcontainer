# devenv-module-devcontainer

A [devenv](https://devenv.sh) module that provides enhanced devcontainer integration with support for multiple container runtimes.

## Features

- Generates `.devcontainer.json` automatically for VS Code devcontainer integration
- Supports multiple container runtime modes:
  - **docker** - Support Docker as the container runtime (default)
  - **podman** - Support Podman with rootless containers
  - **builtin** - Fully self-contained setup with Podman and VS Code included via Nix

## Installation

Add this module to your `devenv.nix` imports or include it in your devenv configuration.

## Usage

### Container Runtime Modes

#### Docker Mode (default)

```nix
{
  devcontainer.mode = "docker";
}
```

#### Podman Mode

For rootless container support with Podman:

```nix
{
  devcontainer.mode = "podman";
}
```

##### VSCode Settings for Podman

When using Podman as the container runtime, configure VSCode to use Podman instead of Docker:

1. Open VSCode Settings (Cmd/Ctrl + ,)
2. Search for "dev containers docker path"
3. Set `dev.containers.dockerPath` to `podman`

Or add to your `settings.json`:

```json
{
  "dev.containers.dockerPath": "podman",
  "dev.containers.dockerSocketPath": "/var/run/user/1000/podman/podman.sock"
}
```

#### Builtin Mode

Provides a fully self-contained development environment with Podman and VS Code installed via Nix:

```nix
{
  devcontainer.mode = "builtin";
}
```

This mode automatically includes:
- Podman and related tools (crun, conmon, skopeo, slirp4netns, fuse-overlayfs)
- VS Code with the Remote Containers extension pre-installed

### Customizing VS Code Extensions

```nix
{
  devcontainer.settings.customizations.vscode.extensions = [
    "mkhl.direnv"
    "bbenoist.Nix"
    "vscodevim.vim"
  ];
}
```

Default extensions: `mkhl.direnv`, `bbenoist.Nix`

### Custom Container Image

```nix
{
  devcontainer.settings.image = "ghcr.io/cachix/devenv/devcontainer:latest";
}
```

### Additional Settings

You can pass any valid devcontainer settings:

```nix
{
  devcontainer.settings = {
    updateContentCommand = "devenv shell -- echo Ready.";
    overrideCommand = false;
    # ... any other devcontainer.json options
  };
}
```

### Network Mode

Configure the container network mode. Currently supports host networking:

```nix
{
  devcontainer.settings.networkMode = "host";
}
```

This option works with all container modes:
- **docker**: Uses `--network=host` to share the host's network namespace
- **podman**: Uses `--network=host` for host networking
- **builtin**: Same as podman mode

When set to `"host"`, the container shares the host's network stack, allowing direct access to host network interfaces and services. This is useful for:
- Accessing services running on the host without port forwarding
- Testing network applications that need specific ports
- Developing network tools that require low-level network access

**Default**: `null` (uses bridge networking)

## Local Configuration

For personal settings that shouldn't be committed, create a `devenv.local.nix` file. See `devenv.local.nix.example` for reference:

```nix
{
  devcontainer.mode = "builtin";
  devcontainer.settings.customizations.vscode.extensions = [
    "mkhl.direnv"
    "bbenoist.Nix"
    "vscodevim.vim"
  ];
}
```

## Direnv Integration

For automatic environment configuration when opening the devcontainer, use direnv with an `.envrc` file:

### Setup

1. Create an `.envrc` file in your project root:

```bash
use devenv
```

2. Allow direnv to execute:

```bash
direnv allow
```

### How It Works

When you have the `mkhl.direnv` VSCode extension installed (included by default in this module):

1. The `.envrc` file tells direnv to use the devenv shell environment
2. When you reopen in the devcontainer, direnv automatically loads the devenv environment
3. Your shell inside the container will have all environment variables, PATH modifications, and tools configured by devenv
4. Changes to `devenv.nix` are automatically picked up when you reload the direnv environment

### Benefits

- **Automatic activation**: No need to manually run `devenv shell` inside the container
- **Consistent environment**: Ensures all terminals and processes use the devenv configuration
- **Hot reload**: Environment updates when you modify `devenv.nix` and reload direnv
- **Editor integration**: VSCode extensions and language servers automatically use the correct environment

### Troubleshooting

If the environment isn't loading automatically:

```bash
# Inside the container
direnv allow
# Or reload manually
direnv reload
```

## How It Works

1. When you enter the devenv shell, the module generates a `.devcontainer.json` file in your project root
2. In `podman` or `builtin` mode, it configures rootless containers with proper user namespace mapping
3. In `builtin` mode, it also sets up Podman configuration files and optionally starts the Podman socket via systemd

## Quick Start

```bash
# Enter the devenv shell (generates .devcontainer.json)
make shell
# or
devenv shell
```

Then open the project in VS Code and use the "Reopen in Container" command.

## License

See LICENSE file for details.
