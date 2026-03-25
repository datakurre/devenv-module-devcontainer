# GitLab allowlist — gitlab.com hosted service.
# Self-managed instances need their own hostnames in allowedHosts.
{
  hosts = [
    "gitlab.com"            # web, git, API
    "registry.gitlab.com"   # GitLab Container Registry
    "packages.gitlab.com"   # GitLab Packages (apt/yum/etc.)
  ];

  cidrs = [];
}
