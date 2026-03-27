# Go allowlist — Go module proxy and checksum database.
#
# Covers `go get`, `go mod download`, `go install`, and module verification.
# storage.googleapis.com hosts the module ZIP files served by proxy.golang.org.
#
# telemetry.go.dev is intentionally omitted; disable telemetry with:
#   go telemetry off
{
  hosts = [
    "proxy.golang.org"        # Go module proxy (default GOPROXY)
    "sum.golang.org"          # Go checksum database (module verification)
    "storage.googleapis.com"  # module ZIP storage backing the proxy
  ];

  cidrs = [];
}
