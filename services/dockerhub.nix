# Docker Hub allowlist — pulling and pushing images to hub.docker.com.
{
  hosts = [
    "registry-1.docker.io"              # image layer / manifest endpoint
    "auth.docker.io"                    # token authentication
    "index.docker.io"                   # legacy v1 index (still used by some clients)
    "hub.docker.com"                    # website API used by Docker Desktop
    "production.cloudflare.docker.com"  # CDN used for large layer pulls
  ];

  cidrs = [];
}
