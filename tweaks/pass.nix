{ lib }:
{
  settings =
    cfg:
    lib.optionalAttrs (lib.elem "pass" cfg.tweaks) {
      mounts = [
        "source=\${localEnv:HOME}/.password-store,target=/home/vscode/.password-store,type=bind,readonly"
      ];
    };
}
