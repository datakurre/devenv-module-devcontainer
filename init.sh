#!/usr/bin/env bash
# devenv-init: Interactive wizard to scaffold devenv.local.nix, devenv.local.yaml,
# and (if absent) devenv.nix for projects using devenv-module-devcontainer.
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_file() {
  local path="$1"
  local content="$2"
  if [[ -f "$path" ]]; then
    gum style --foreground 214 "  $path already exists."
    if ! gum confirm "Overwrite $path?"; then
      gum style --foreground 240 "  Skipped $path."
      return
    fi
  fi
  printf '%s\n' "$content" > "$path"
  gum style --foreground 82 "  Created $path"
}

join_nix_list() {
  # Takes newline-separated values, outputs Nix list items with leading spaces
  local indent="${1:-      }"
  while IFS= read -r item; do
    [[ -n "$item" ]] && printf '%s"%s"\n' "$indent" "$item"
  done
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

gum style \
  --border rounded --border-foreground 99 \
  --padding "1 2" --margin "1 0" \
  "devenv-module-devcontainer init"

gum style --foreground 240 \
  "Scaffolds devenv.local.nix, devenv.local.yaml, and devenv.nix in the current directory."
echo

# ---------------------------------------------------------------------------
# 1. Module URL
# ---------------------------------------------------------------------------

gum style --bold "Module URL"
gum style --foreground 240 "URL for devenv-module-devcontainer (written into devenv.local.yaml)"
MODULE_URL=$(gum input \
  --placeholder "git+https://gitlab.kopla.jyu.fi/nix/devenv-module-devcontainer" \
  --value "git+https://gitlab.kopla.jyu.fi/nix/devenv-module-devcontainer")
echo

# ---------------------------------------------------------------------------
# 2. Tweaks
# ---------------------------------------------------------------------------

gum style --bold "Tweaks"
gum style --foreground 240 "Select the devcontainer tweaks to enable (space to toggle, enter to confirm)"
TWEAKS=$(gum choose --no-limit \
  --selected "gpg-agent,vscode" \
  "cli" "gpg-agent" "netrc" "pass" "podman" "rootless" "vscode")
echo

# ---------------------------------------------------------------------------
# 3. netrc path (if netrc tweak selected)
# ---------------------------------------------------------------------------

NETRC_PATH=""
if echo "$TWEAKS" | grep -q "^netrc$"; then
  gum style --bold "netrc path"
  gum style --foreground 240 "Path to your .netrc file on the host"
  NETRC_PATH=$(gum input \
    --placeholder "$HOME/.netrc" \
    --value "$HOME/.netrc")
  echo
fi

# ---------------------------------------------------------------------------
# 4. Network mode
# ---------------------------------------------------------------------------

gum style --bold "Network mode"
NETWORK_MODE=$(gum choose \
  --selected "bridge" \
  "bridge" "named" "host" "none")
echo

# ---------------------------------------------------------------------------
# 5. Named network details
# ---------------------------------------------------------------------------

NETWORK_NAME=""
NETWORK_HOSTNAME=""
if [[ "$NETWORK_MODE" == "named" ]]; then
  gum style --bold "Named network — network name"
  NETWORK_NAME=$(gum input --placeholder "devenv")
  gum style --bold "Named network — container hostname"
  NETWORK_HOSTNAME=$(gum input --placeholder "$(basename "$PWD")")
  echo
fi

# ---------------------------------------------------------------------------
# 6. Languages (VS Code extensions + firewall allowedServices)
# ---------------------------------------------------------------------------

gum style --bold "Languages"
gum style --foreground 240 "Select the languages you work with (adds VS Code extensions and firewall service rules)"
LANGUAGES=$(gum choose --no-limit \
  "C/C++" "Go" "Haskell" "Java" "JavaScript/TypeScript" "Lua" "Nix" "Python" "Rust")
echo

# Map languages to VS Code extension IDs
EXTRA_EXTENSIONS=""
ALLOWED_SERVICES=""

add_ext()  { EXTRA_EXTENSIONS="${EXTRA_EXTENSIONS}${1}"$'\n'; }
add_svc()  { ALLOWED_SERVICES="${ALLOWED_SERVICES}${1}"$'\n'; }

if echo "$LANGUAGES" | grep -q "^C/C++$";               then add_ext "ms-vscode.cpptools"; fi
if echo "$LANGUAGES" | grep -q "^Go$";                   then add_ext "golang.go";          add_svc "go"; fi
if echo "$LANGUAGES" | grep -q "^Haskell$";              then add_ext "haskell.haskell";    add_svc "haskell"; fi
if echo "$LANGUAGES" | grep -q "^Java$";                 then add_ext "vscjava.vscode-java-pack"; add_svc "java"; fi
if echo "$LANGUAGES" | grep -q "^JavaScript/TypeScript$"; then
  add_ext "dbaeumer.vscode-eslint"
  add_ext "esbenp.prettier-vscode"
  add_svc "javascript"
fi
if echo "$LANGUAGES" | grep -q "^Lua$";    then add_ext "sumneko.lua"; fi
# Nix is always included via jnoortheen.nix-ide (added to base list below)
if echo "$LANGUAGES" | grep -q "^Python$"; then add_ext "ms-python.python"; add_svc "python"; fi
if echo "$LANGUAGES" | grep -q "^Rust$";   then add_ext "rust-lang.rust-analyzer"; fi

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------

echo
gum style --bold --foreground 99 "Summary"
gum style "  Module URL : $MODULE_URL"
gum style "  Tweaks     : $(echo "$TWEAKS" | tr '\n' ' ')"
[[ -n "$NETRC_PATH" ]]      && gum style "  netrc path : $NETRC_PATH"
gum style "  Network    : $NETWORK_MODE"
[[ -n "$NETWORK_NAME" ]]    && gum style "  Net name   : $NETWORK_NAME  hostname: $NETWORK_HOSTNAME"
[[ -n "$LANGUAGES" ]]       && gum style "  Languages  : $(echo "$LANGUAGES" | tr '\n' ' ')"
echo

if ! gum confirm "Write files?"; then
  gum style --foreground 214 "Aborted."
  exit 0
fi
echo

# ---------------------------------------------------------------------------
# 8. Build file contents
# ---------------------------------------------------------------------------

# --- devenv.local.yaml ---

YAML_CONTENT="inputs:
  devenv-module-devcontainer:
    url: ${MODULE_URL}
    flake: false
  devenv-module-devcontainer-nixpkgs:
    url: github:nixos/nixpkgs
imports:
  - devenv-module-devcontainer"

# --- devenv.local.nix ---

build_nix_local() {
  local tweaks_nix=""
  while IFS= read -r t; do
    [[ -n "$t" ]] && tweaks_nix="${tweaks_nix}      \"${t}\"\n"
  done <<< "$TWEAKS"

  # Base VS Code extensions
  local exts="      \"GitHub.copilot\"\n      \"GitHub.copilot-chat\"\n      \"datakurre.devenv\"\n      \"jnoortheen.nix-ide\""
  while IFS= read -r e; do
    [[ -n "$e" ]] && exts="${exts}\n      \"${e}\""
  done <<< "$EXTRA_EXTENSIONS"

  local out
  out="{"
  out="${out}
  profiles.devcontainer.module = {"
  out="${out}
    devcontainer.enable = true;"

  # netrc
  if [[ -n "$NETRC_PATH" ]]; then
    out="${out}
    devcontainer.netrc = \"${NETRC_PATH}\";"
  fi

  # network
  if [[ "$NETWORK_MODE" != "bridge" ]]; then
    out="${out}
    devcontainer.network.mode = \"${NETWORK_MODE}\";"
    if [[ "$NETWORK_MODE" == "named" ]]; then
      [[ -n "$NETWORK_NAME" ]] && out="${out}
    devcontainer.network.name = \"${NETWORK_NAME}\";"
      [[ -n "$NETWORK_HOSTNAME" ]] && out="${out}
    devcontainer.network.hostname = \"${NETWORK_HOSTNAME}\";"
    fi
  fi

  # allowedServices
  if [[ -n "$ALLOWED_SERVICES" ]] && [[ "$NETWORK_MODE" == "bridge" || "$NETWORK_MODE" == "named" ]]; then
    local svcs_nix=""
    while IFS= read -r s; do
      [[ -n "$s" ]] && svcs_nix="${svcs_nix}      \"${s}\"\n"
    done <<< "$ALLOWED_SERVICES"
    out="${out}
    devcontainer.network.allowedServices = [
$(printf '%b' "$svcs_nix")    ];"
  fi

  # tweaks
  if [[ -n "$TWEAKS" ]]; then
    out="${out}
    devcontainer.tweaks = [
$(printf '%b' "$tweaks_nix")    ];"
  fi

  # extensions
  out="${out}
    devcontainer.settings.customizations.vscode.extensions = [
$(printf '%b' "$exts")
    ];
  };"
  out="${out}
}"

  printf '%s' "$out"
}

NIX_LOCAL_CONTENT=$(build_nix_local)

# --- devenv.nix (empty stub only if absent) ---

NIX_STUB="{ }"

# ---------------------------------------------------------------------------
# 9. Write files
# ---------------------------------------------------------------------------

write_file "devenv.local.yaml" "$YAML_CONTENT"
write_file "devenv.local.nix"  "$NIX_LOCAL_CONTENT"

if [[ ! -f "devenv.nix" ]]; then
  write_file "devenv.nix" "$NIX_STUB"
else
  gum style --foreground 240 "  devenv.nix already exists — not touched."
fi

echo
gum style --bold --foreground 82 "Done. Next steps:"
gum style "  1. Review the generated files."
gum style "  2. Run: devenv shell --profile=devcontainer -- code ."
