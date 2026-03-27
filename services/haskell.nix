# Haskell allowlist — Hackage, GHCup, and Stack binary downloads.
#
# Covers cabal, stack, and ghcup workflows:
#   - hackage.haskell.org  — Hackage package index and tarballs (cabal)
#   - downloads.haskell.org — GHC, Cabal, HLS, and Stack binaries (ghcup + stack setup)
#
# GHCup channel metadata YAMLs, Stackage snapshots, and HLS/Stack releases
# are fetched from GitHub (covered by the github service).
{
  hosts = [
    "hackage.haskell.org"     # Hackage package index and tarballs
    "downloads.haskell.org"   # GHC / Cabal / HLS / Stack binary distributions
  ];

  cidrs = [];
}
