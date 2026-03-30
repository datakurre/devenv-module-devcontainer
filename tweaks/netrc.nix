{ lib }:
{
  settings =
    cfg:
    lib.optionalAttrs (lib.elem "netrc" cfg.tweaks) (
      assert lib.assertMsg (cfg.netrc != null) "devcontainer.netrc must be set when using 'netrc' tweak";
      {
        mounts = [
          "source=${cfg.netrc},target=/home/vscode/.netrc,type=bind,readonly"
        ];
        onCreateCommand = "mkdir -p /home/vscode/.config/nix && echo 'extra-sandbox-paths = /tmp/.netrc' > /home/vscode/.config/nix/nix.conf && cat /home/vscode/.netrc > /tmp/.netrc";
        containerEnv.NETRC = "/tmp/.netrc";
      }
    );
}
