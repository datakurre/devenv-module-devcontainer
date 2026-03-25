# Curated outbound allowlist definitions for common services.
# Each service exposes { hosts = [...]; cidrs = [...]; }.
# Imported by devcontainer-firewall.nix (to build nft rules) and by
# devenv.nix (to derive the enum type for allowedServices).
{
  anthropic = import ./anthropic.nix;
  cachix    = import ./cachix.nix;
  dockerhub = import ./dockerhub.nix;
  github    = import ./github.nix;
  gitlab    = import ./gitlab.nix;
  google    = import ./google.nix;
  nixpkgs   = import ./nixpkgs.nix;
  npm       = import ./npm.nix;
  openai    = import ./openai.nix;
  pypi      = import ./pypi.nix;
}
