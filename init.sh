# devenv-init: Interactive wizard to scaffold devenv.yaml, devenv.nix,
# devenv.local.nix, and devenv.local.yaml for projects using devenv-module-devcontainer.
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

LAST_WRITE_DONE=0

write_file() {
  local path="$1"
  local content="$2"
  LAST_WRITE_DONE=0
  if [[ -f "$path" ]]; then
    gum style --foreground 214 "  $path already exists."
    if ! gum confirm "Overwrite $path?"; then
      gum style --foreground 240 "  Skipped $path."
      return
    fi
  fi
  printf '%s\n' "$content" > "$path"
  LAST_WRITE_DONE=1
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
  "Scaffolds devenv.yaml, devenv.nix, devenv.local.nix, and devenv.local.yaml in the current directory."
echo

# ---------------------------------------------------------------------------
# 1. Module URL
# ---------------------------------------------------------------------------

# Derive a devenv input URL from the flake source URL embedded at build time.
# Handles three cases:
#   https://host/path.git?rev=... → git+https://host/path  (nix run https://...)
#   git+https://host/path?rev=... → git+https://host/path  (nix run git+https://...)
#   path:/... or empty            → empty (local dev / unknown)
_guess_module_url() {
  local url="${FLAKE_SOURCE_URL:-}"
  # Strip query string (?rev=... etc.)
  url="${url%%\?*}"
  # Convert plain https:// to git+https:// and strip .git suffix
  if [[ "$url" == https://* ]]; then
    url="git+https://${url#https://}"
    url="${url%.git}"
  fi
  # Only return git+https:// URLs; discard path: or empty
  if [[ "$url" == git+https://* ]]; then
    echo "$url"
  fi
}
_GUESSED_URL=$(_guess_module_url)

gum style --bold "Module URL"
gum style --foreground 240 "URL for devenv-module-devcontainer (written into devenv.local.yaml)"
MODULE_URL=$(gum input \
  --placeholder "git+https://gitlab.kopla.jyu.fi/nix/devenv-module-devcontainer" \
  --value "${_GUESSED_URL:-}")
echo

# ---------------------------------------------------------------------------
# 2. Tweaks
# ---------------------------------------------------------------------------

gum style --bold "Tweaks"
gum style --foreground 240 "Select the devcontainer tweaks to enable (space to toggle, enter to confirm)"
TWEAKS=$(gum choose --no-limit \
  --selected "gpg-agent,vscode" \
  "devcontainer" "gpg-agent" "netrc" "podman" "vscode")
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
  "bridge" "named" "host")
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
# 6. VS Code extensions
# ---------------------------------------------------------------------------

gum style --bold "VS Code extensions"
gum style --foreground 240 "Select extensions to install (space to toggle, enter to confirm)"
_RAW_EXTENSIONS=$(gum choose --no-limit \
  --header "AI / Coding agents · DevEnv / Nix · Python · Go/Rust/C++ · JVM/Haskell · Web · Lua · Editor" \
  --selected "GitHub.copilot — GitHub Copilot,GitHub.copilot-chat — GitHub Copilot Chat,datakurre.devenv — devenv for VS Code,jnoortheen.nix-ide — Nix IDE" \
  "GitHub.copilot — GitHub Copilot" \
  "GitHub.copilot-chat — GitHub Copilot Chat" \
  "openai.chatgpt — OpenAI Codex (ChatGPT)" \
  "anthropic.claude-code — Claude Code (Anthropic)" \
  "Continue.continue — Continue" \
  "Cline.cline — Cline" \
  "datakurre.devenv — devenv for VS Code" \
  "jnoortheen.nix-ide — Nix IDE" \
  "ms-python.python — Python" \
  "ms-python.debugpy — Python Debugger" \
  "ms-python.pylance — Pylance" \
  "charliermarsh.ruff — Ruff" \
  "d-biehl.robotcode — RobotCode" \
  "golang.go — Go" \
  "rust-lang.rust-analyzer — rust-analyzer" \
  "ms-vscode.cpptools — C/C++" \
  "vscjava.vscode-java-pack — Extension Pack for Java" \
  "haskell.haskell — Haskell" \
  "Elmtooling.elm-ls-vscode — Elm" \
  "dbaeumer.vscode-eslint — ESLint" \
  "esbenp.prettier-vscode — Prettier" \
  "redhat.vscode-yaml — YAML (Red Hat)" \
  "tamasfe.even-better-toml — Even Better TOML" \
  "sumneko.lua — Lua" \
  "vscodevim.vim — Vim")
# Strip " — Title" suffix to keep only extension IDs
SELECTED_EXTENSIONS=$(printf '%s\n' "$_RAW_EXTENSIONS" | sed 's/ — .*//')
echo

# Derive allowedServices from selected extensions
ALLOWED_SERVICES=""
add_svc() { ALLOWED_SERVICES="${ALLOWED_SERVICES}${1}"$'\n'; }

echo "$SELECTED_EXTENSIONS" | grep -q "^openai\.chatgpt$"              && add_svc "openai"
echo "$SELECTED_EXTENSIONS" | grep -q "^anthropic\.claude-code$"       && add_svc "claude"
echo "$SELECTED_EXTENSIONS" | grep -q "^golang\.go$"                   && add_svc "go"
echo "$SELECTED_EXTENSIONS" | grep -q "^haskell\.haskell$"             && add_svc "haskell"
echo "$SELECTED_EXTENSIONS" | grep -q "^Elmtooling\.elm-ls-vscode$"     && add_svc "elm"
echo "$SELECTED_EXTENSIONS" | grep -q "^vscjava\.vscode-java-pack$"    && add_svc "java"
echo "$SELECTED_EXTENSIONS" | grep -qE "^(dbaeumer\.vscode-eslint|esbenp\.prettier-vscode)$" && add_svc "javascript"
echo "$SELECTED_EXTENSIONS" | grep -q "^ms-python\.python$"            && add_svc "python"

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
[[ -n "$SELECTED_EXTENSIONS" ]] && gum style "  Extensions : $(echo "$SELECTED_EXTENSIONS" | tr '\n' ' ')"
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

  # VS Code extensions — use selection directly
  local exts=""
  while IFS= read -r e; do
    [[ -n "$e" ]] && exts="${exts}      \"${e}\"\n"
  done <<< "$SELECTED_EXTENSIONS"

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

# --- devenv.yaml ---

DEVENV_YAML_CONTENT="# yaml-language-server: \$schema=https://devenv.sh/devenv.schema.json"

# --- devenv.nix stub ---

NIX_STUB='{
  profiles.shell.module = {pkgs, ...}: {
  };
}'

# ---------------------------------------------------------------------------
# 9. Write files
# ---------------------------------------------------------------------------

write_file "devenv.yaml"       "$DEVENV_YAML_CONTENT"
write_file "devenv.local.yaml" "$YAML_CONTENT"
write_file "devenv.local.nix"  "$NIX_LOCAL_CONTENT"
[[ "$LAST_WRITE_DONE" == 1 ]] && nixfmt devenv.local.nix
write_file "devenv.nix"        "$NIX_STUB"
[[ "$LAST_WRITE_DONE" == 1 ]] && nixfmt devenv.nix

echo
gum style --bold --foreground 82 "Done. Next steps:"
gum style "  1. Review the generated files."
gum style "  2. Run: devenv shell --profile=devcontainer -- code ."
