# GitHub allowlist — hostnames and IP ranges for github.com and its CDN.
#
# Hosts: key GitHub hostnames resolved via getent at container start.
#
# CIDRs: full IP range union of categories web, api, git, hooks, pages,
#        packages, copilot, services, dependabot from the GitHub meta endpoint.
#        GitHub Actions Azure ranges are intentionally excluded — they are
#        hundreds of /24 blocks covering unrelated Azure tenants. Add specific
#        ranges via allowedHosts if you need to reach webhook receivers or
#        self-hosted runners from inside the container.
#
# Source:  https://api.github.com/meta
# Updated: 2026-03-25
#
# To refresh:
#   curl -fsSL https://api.github.com/meta | python3 -c "
#   import json,sys
#   d=json.load(sys.stdin)
#   cats=['web','api','git','hooks','pages','packages','copilot','services','dependabot']
#   cidrs=sorted(set(c for k in cats for c in d.get(k,[])))
#   for c in cidrs: print(c)"
{
  hosts = [
    "github.com"
    "api.github.com"
    "raw.githubusercontent.com"
    "objects.githubusercontent.com"
    "githubusercontent.com"
    "codeload.github.com"
    "uploads.github.com"
    "ghcr.io"          # GitHub Container Registry
    "pkg.github.com"   # GitHub Packages (npm, Maven, …)
  ];

  cidrs = [
    # ── GitHub-owned network blocks (stable) ──────────────────────────────
    "140.82.112.0/20"   # github.com main network
    "143.55.64.0/20"    # github.com secondary network
    "185.199.108.0/22"  # GitHub CDN / raw.githubusercontent.com
    "192.30.252.0/22"   # GitHub main infrastructure / hooks

    # ── GitHub on Azure (git, api, packages, copilot, dependabot) ─────────
    # These /32 addresses are individual Azure VMs; they change more often
    # than the blocks above. Re-run the refresh command when updating.
    "13.107.5.93/32"
    "138.91.182.224/32"
    "20.175.192.146/32"
    "20.175.192.147/32"
    "20.175.192.149/32"
    "20.175.192.150/32"
    "20.199.39.224/32"
    "20.199.39.227/32"
    "20.199.39.228/32"
    "20.199.39.231/32"
    "20.199.39.232/32"
    "20.200.245.241/32"
    "20.200.245.245/32"
    "20.200.245.247/32"
    "20.200.245.248/32"
    "20.201.28.144/32"
    "20.201.28.148/32"
    "20.201.28.151/32"
    "20.201.28.152/32"
    "20.205.243.160/32"
    "20.205.243.164/32"
    "20.205.243.166/32"
    "20.205.243.168/32"
    "20.207.73.82/32"
    "20.207.73.83/32"
    "20.207.73.85/32"
    "20.207.73.86/32"
    "20.217.135.0/32"
    "20.217.135.1/32"
    "20.217.135.4/32"
    "20.217.135.5/32"
    "20.233.83.145/32"
    "20.233.83.146/32"
    "20.233.83.147/32"
    "20.233.83.149/32"
    "20.250.119.64/32"
    "20.26.156.210/32"
    "20.26.156.211/32"
    "20.26.156.214/32"
    "20.26.156.215/32"
    "20.27.177.113/32"
    "20.27.177.116/32"
    "20.27.177.117/32"
    "20.27.177.118/32"
    "20.29.134.17/32"
    "20.29.134.18/32"
    "20.29.134.19/32"
    "20.29.134.23/32"
    "20.85.130.105/32"
    "20.87.245.0/32"
    "20.87.245.1/32"
    "20.87.245.4/32"
    "20.87.245.6/32"
    "4.208.26.196/32"
    "4.208.26.197/32"
    "4.208.26.198/32"
    "4.208.26.200/32"
    "4.225.11.192/32"
    "4.225.11.194/32"
    "4.225.11.196/32"
    "4.225.11.200/32"
    "4.225.11.201/32"
    "4.228.31.145/32"
    "4.228.31.149/32"
    "4.228.31.150/32"
    "4.228.31.152/32"
    "4.228.31.153/32"
    "4.237.22.32/32"
    "4.237.22.34/32"
    "4.237.22.38/32"
    "4.237.22.40/32"
    "4.237.22.41/32"
    "4.249.131.160/32"
    "52.140.63.241/32"
    "52.175.140.176/32"

    # ── IPv6 ───────────────────────────────────────────────────────────────
    "2606:50c0::/32"    # GitHub CDN IPv6
    "2a0a:a440::/29"    # GitHub infrastructure IPv6
  ];
}
