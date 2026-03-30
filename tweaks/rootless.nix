{ lib }:
{
  settings =
    cfg:
    lib.optionalAttrs (lib.elem "rootless" cfg.tweaks || lib.elem "podman" cfg.tweaks) {
      containerUser = "vscode";
      containerEnv.HOME = "/home/vscode";
      runArgs = [ "--userns=keep-id" ];
    };
}
