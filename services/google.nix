# Google allowlist — googleapis.com, GCS, GCR, Artifact Registry, and OAuth.
# Covers the most common Google Cloud client operations from a devcontainer.
#
# Hosts: key Google hostnames for auth, storage, container registries, and APIs.
#
# CIDRs: all IPv4 prefixes from the Google IP ranges JSON feed (goog.json).
#        This covers Google's entire routable address space including GCP,
#        Workspace, and other Google services.
#
# Source:  https://www.gstatic.com/ipranges/goog.json
# Updated: 2026-03-30
#
# To refresh:
#   curl -fsSL https://www.gstatic.com/ipranges/goog.json | python3 -c "
#   import json,sys
#   d=json.load(sys.stdin)
#   cidrs=sorted(set(e['ipv4Prefix'] for e in d.get('prefixes',[]) if 'ipv4Prefix' in e))
#   print('# syncToken:', d.get('syncToken'), '  creationTime:', d.get('creationTime'))
#   for c in cidrs: print(c)"
{
  hosts = [
    "google.com"                    # Google search
    "www.google.com"                # Google search
    "accounts.google.com"           # OAuth 2.0 / OIDC authentication
    "oauth2.googleapis.com"         # OAuth token endpoint
    "www.googleapis.com"            # REST discovery / fallback endpoint used by GCP client libraries
    "iam.googleapis.com"            # IAM API
    "storage.googleapis.com"        # Google Cloud Storage JSON API
    "storage-download.googleapis.com" # GCS media / resumable download
    "gcr.io"                        # Google Container Registry (legacy)
    "pkg.dev"                       # Artifact Registry (all regions resolve here)
    "www.gstatic.com"               # Google APIs client library dependencies
  ];

  # syncToken: 1774857872875  creationTime: 2026-03-30T01:04:32.875286
  cidrs = [
    "8.8.4.0/24"
    "8.8.8.0/24"
    "8.34.208.0/20"
    "8.35.192.0/20"
    "8.228.0.0/14"
    "8.232.0.0/14"
    "8.236.0.0/15"
    "23.236.48.0/20"
    "23.251.128.0/19"
    "34.0.0.0/15"
    "34.2.0.0/16"
    "34.3.0.0/23"
    "34.3.3.0/24"
    "34.3.4.0/24"
    "34.3.8.0/21"
    "34.3.16.0/20"
    "34.3.32.0/19"
    "34.3.64.0/18"
    "34.4.0.0/14"
    "34.8.0.0/13"
    "34.16.0.0/12"
    "34.32.0.0/11"
    "34.64.0.0/10"
    "34.128.0.0/10"
    "35.184.0.0/13"
    "35.192.0.0/14"
    "35.196.0.0/15"
    "35.198.0.0/16"
    "35.199.0.0/17"
    "35.199.128.0/18"
    "35.200.0.0/13"
    "35.208.0.0/12"
    "35.224.0.0/12"
    "35.240.0.0/13"
    "35.252.0.0/14"
    "64.15.112.0/20"
    "64.233.160.0/19"
    "66.102.0.0/20"
    "66.249.64.0/19"
    "70.32.128.0/19"
    "72.14.192.0/18"
    "74.114.24.0/21"
    "74.125.0.0/16"
    "104.154.0.0/15"
    "104.196.0.0/14"
    "104.237.160.0/19"
    "107.167.160.0/19"
    "107.178.192.0/18"
    "108.59.80.0/20"
    "108.170.192.0/18"
    "108.177.0.0/17"
    "130.211.0.0/16"
    "136.22.2.0/23"
    "136.22.4.0/23"
    "136.22.8.0/22"
    "136.22.160.0/20"
    "136.22.176.0/21"
    "136.22.184.0/23"
    "136.22.186.0/24"
    "136.23.48.0/20"
    "136.23.64.0/18"
    "136.64.0.0/11"
    "136.107.0.0/16"
    "136.108.0.0/14"
    "136.112.0.0/13"
    "136.120.0.0/22"
    "136.124.0.0/15"
    "142.250.0.0/15"
    "146.148.0.0/17"
    "162.120.128.0/17"
    "162.216.148.0/22"
    "162.222.176.0/21"
    "172.110.32.0/21"
    "172.217.0.0/16"
    "172.253.0.0/16"
    "173.194.0.0/16"
    "173.255.112.0/20"
    "192.104.160.0/23"
    "192.158.28.0/22"
    "192.178.0.0/15"
    "193.186.4.0/24"
    "199.36.154.0/23"
    "199.36.156.0/24"
    "199.192.112.0/22"
    "199.223.232.0/21"
    "207.175.0.0/16"
    "207.223.160.0/20"
    "208.65.152.0/22"
    "208.68.108.0/22"
    "208.81.188.0/22"
    "208.117.224.0/19"
    "209.85.128.0/17"
    "216.58.192.0/19"
    "216.73.80.0/20"
    "216.239.32.0/19"
    "216.252.220.0/22"
  ];
}
