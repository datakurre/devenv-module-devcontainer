{ lib, pkgsDevcontainer }:
{
  packages =
    cfg:
    lib.optionals (lib.elem "devcontainer" cfg.tweaks) [
      pkgsDevcontainer.devcontainer
    ];
}
