{ lib, pkgsDevcontainer }:
{
  packages =
    cfg:
    lib.optionals (lib.elem "antigravity" cfg.tweaks) [
      pkgsDevcontainer.antigravity
    ];
  settings =
    cfg:
    lib.optionalAttrs (lib.elem "antigravity" cfg.tweaks) {
      mounts = [
        "source=\${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,readonly"
      ];
      postStartCommand = "(git config --get user.signingkey | xargs -I {} gpg --keyserver keyserver.ubuntu.com --recv-keys {} || true)";
    };
}
