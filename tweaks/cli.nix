{ lib, pkgsDevcontainer }:
{
  packages =
    cfg:
    lib.optionals (lib.elem "cli" cfg.tweaks) [
      pkgsDevcontainer.devcontainer
    ];
}
