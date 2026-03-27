# Curated outbound allowlist definitions for common services.
# Each service exposes { hosts = [...]; cidrs = [...]; }.
# Imported by devcontainer-firewall.nix (to build nft rules) and by
# devenv.nix (to derive the enum type for allowedServices).
{
  azure     = import ./azure.nix;
  claude    = import ./claude.nix;
  dockerhub = import ./dockerhub.nix;
  elm       = import ./elm.nix;
  github    = import ./github.nix;
  gitlab    = import ./gitlab.nix;
  go        = import ./go.nix;
  google    = import ./google.nix;
  haskell   = import ./haskell.nix;
  java      = import ./java.nix;
  nix       = import ./nix.nix;
  npm       = import ./npm.nix;
  openai    = import ./openai.nix;
  python    = import ./python.nix;
}
