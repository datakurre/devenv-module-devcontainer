{ lib, pkgsDevcontainer }:
{
  packages =
    cfg:
    lib.optionals (lib.elem "antigravity" cfg.tweaks) [
      pkgsDevcontainer.antigravity
    ];
}
