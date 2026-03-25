# Cachix allowlist — cachix.org binary cache platform.
#
# This covers the Cachix website and the auth/API endpoints used by the
# `cachix` CLI when pushing or pulling from any cache.
#
# Each individual cache subdomain (e.g. devenv.cachix.org,
# nix-community.cachix.org) must be added separately via allowedHosts,
# because they vary per project.
{
  hosts = [
    "cachix.org"       # API, auth, and cache metadata
    "app.cachix.org"   # web dashboard (accessed by cachix CLI for token setup)
  ];

  cidrs = [];
}
