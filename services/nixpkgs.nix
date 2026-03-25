# NixOS binary cache allowlist — official NixOS substituter and release channels.
# This covers `nix build`, `nix shell`, and `devenv` fetches via cache.nixos.org.
#
# Community caches hosted on Cachix (e.g. nix-community.cachix.org,
# devenv.cachix.org) are NOT included here; use the cachix service for the
# cachix.org domain, and add specific subdomain caches to allowedHosts.
{
  hosts = [
    "cache.nixos.org"     # official NixOS binary cache (Fastly CDN)
    "channels.nixos.org"  # channel index / narinfo redirects
    "releases.nixos.org"  # ISO and tarball downloads
  ];

  cidrs = [];
}
