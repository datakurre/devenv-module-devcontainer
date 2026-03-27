# Elm allowlist — Elm package registry.
#
# package.elm-lang.org is the only Elm-specific endpoint.
# Package archives are ZIP files hosted on GitHub (covered by the github service).
{
  hosts = [
    "package.elm-lang.org"  # package registry — metadata, install, publish
  ];

  cidrs = [];
}
