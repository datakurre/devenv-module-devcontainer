{ lib }:
{
  mode = lib.mkOption {
    type = lib.types.enum [
      "bridge"
      "host"
      "none"
      "named"
    ];
    default = "bridge";
    description = ''
      Network mode for the container.
      - "bridge": Use the default bridge network (default)
      - "host": Use host networking (shares the host's network namespace)
      - "none": Disable all networking (complete isolation)
      - "named": Join a named Docker/Podman network specified by network.name.
        Two devcontainers using the same name share that network and can
        reach each other by container name. The network must be pre-created
        before starting the container (e.g. `docker network create my-net`).
    '';
  };

  name = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "my-project-net";
    description = ''
      Name of the Docker/Podman network to join when network.mode = "named".
      Must be set whenever network.mode = "named".
    '';
  };

  allowedHosts = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      List of hostnames, IP addresses, or CIDR ranges the container is
      allowed to connect to outbound. When non-empty, all other outbound
      connections are blocked via nftables inside the container.

      Only outbound traffic is filtered; inbound traffic is not blocked.
      This keeps published/forwarded devcontainer service ports reachable.

      Requires network.mode = "bridge" (default) or "named". Each entry is either:
      - a hostname (e.g. "github.com") — resolved at container start via getent
      - a bare IP address (e.g. "192.168.1.10")
      - a CIDR range (e.g. "10.0.0.0/8", "2001:db8::/32")

      Loopback, DNS (port 53), the nameservers listed in /etc/resolv.conf
      (added implicitly so DoT/DoH reaches the configured resolver),
      and already-established connections are
      always permitted regardless of this list.

      Adds --cap-add=NET_ADMIN to runArgs automatically.
    '';
  };

  allowedServices = lib.mkOption {
    type = lib.types.listOf (
      lib.types.enum [
        "azure"
        "claude"
        "dockerhub"
        "elm"
        "github"
        "gitlab"
        "go"
        "google"
        "haskell"
        "java"
        "nix"
        "javascript"
        "openai"
        "python"
      ]
    );
    default = [ ];
    example = [
      "github"
      "openai"
    ];
    description = ''
      Enable curated outbound host allowlists for well-known services.
      Each name adds a hardcoded set of hostnames (and CIDRs for github)
      to the firewall allowlist. Service definitions live in the
      services/ directory of this module.

      These are merged with network.allowedHosts.
      Only outbound traffic is filtered; inbound traffic is not blocked.
    '';
  };

}
