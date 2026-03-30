{ lib }:
{
  settings =
    cfg:
    lib.optionalAttrs (lib.elem "gpg-agent" cfg.tweaks) {
      mounts = [
        "source=\${localEnv:XDG_RUNTIME_DIR}/gnupg/S.gpg-agent,target=/run/host-gpg-agent,type=bind,readonly"
      ];
      remoteEnv.GPG_TTY = "/dev/pts/0";
      postStartCommand = "mkdir -p /home/vscode/.gnupg && rm -f /home/vscode/.gnupg/S.gpg-agent && ln -s /run/host-gpg-agent /home/vscode/.gnupg/S.gpg-agent";
    };
}
