# Google allowlist — googleapis.com, GCS, GCR, Artifact Registry, and OAuth.
# Covers the most common Google Cloud client operations from a devcontainer.
{
  hosts = [
    "accounts.google.com"           # OAuth 2.0 / OIDC authentication
    "oauth2.googleapis.com"         # OAuth token endpoint
    "iam.googleapis.com"            # IAM API
    "storage.googleapis.com"        # Google Cloud Storage JSON API
    "storage-download.googleapis.com" # GCS media / resumable download
    "gcr.io"                        # Google Container Registry (legacy)
    "pkg.dev"                       # Artifact Registry (all regions resolve here)
  ];

  cidrs = [];
}
