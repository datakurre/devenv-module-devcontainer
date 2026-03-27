# Azure allowlist — Azure DevOps, authentication, and Microsoft Container Registry.
#
# Covers az CLI login, Azure DevOps git/API, and MCR image pulls.
#
# NOT includable here (dynamic per-account or per-org subdomains):
#   - *.azurecr.io  — per-account Azure Container Registries; add via allowedHosts
#   - *.visualstudio.com — legacy Azure DevOps org subdomains; add via allowedHosts
{
  hosts = [
    "login.microsoftonline.com"  # Azure AD / Entra ID OAuth 2.0 and OIDC
    "login.microsoft.com"        # legacy auth endpoint (fallback used by some SDKs)
    "management.azure.com"       # Azure Resource Manager API
    "graph.microsoft.com"        # Microsoft Graph API
    "dev.azure.com"              # Azure DevOps (repos, pipelines, artifacts)
    "mcr.microsoft.com"          # Microsoft Container Registry (devcontainer base images + features)
  ];

  cidrs = [];
}
