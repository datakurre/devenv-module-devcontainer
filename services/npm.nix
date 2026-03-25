# npm allowlist — npm registry and Yarn classic registry.
# Note: GitHub Packages npm registry (npm.pkg.github.com) is covered by the
# github service. Scoped registries pointing elsewhere need their own entries
# in allowedHosts.
{
  hosts = [
    "registry.npmjs.org"   # npm package registry
    "www.npmjs.com"        # npm website (package metadata used by some tools)
    "registry.yarnpkg.com" # Yarn classic registry (proxies npmjs.org)
  ];

  cidrs = [];
}
