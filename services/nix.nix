# Nix allowlist — NixOS binary caches, devenv, and Cachix.
#
# Covers:
#   - cache.nixos.org (official NixOS binary cache, Fastly CDN)
#   - cachix.org platform (CLI auth/API for all caches)
#   - devenv.sh (update checks and documentation fetched by the devenv CLI)
#   - devenv.cachix.org (universal devenv binary cache)
#   - nix-community.cachix.org (widely-used community cache)
#
# Per-project caches not listed here (e.g. myproject.cachix.org) must be
# added separately via allowedHosts.
{
  hosts = [
    "cache.nixos.org"              # official NixOS binary cache (Fastly CDN)
    "channels.nixos.org"           # channel index / narinfo redirects
    "releases.nixos.org"           # ISO and tarball downloads
    "cachix.org"                   # Cachix API, auth, and cache metadata
    "app.cachix.org"               # Cachix web dashboard (CLI token setup)
    "devenv.sh"                    # devenv website / update checks
    "devenv.cachix.org"            # devenv universal binary cache
    "nix-community.cachix.org"     # nix-community binary cache
  ];

  cidrs = [];
}
