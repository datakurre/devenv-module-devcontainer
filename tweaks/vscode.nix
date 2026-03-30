{ lib, pkgsDevcontainer }:
{
  packages =
    cfg:
    lib.optionals (lib.elem "vscode" cfg.tweaks) [
      (pkgsDevcontainer.vscode-with-extensions.override {
        vscode = pkgsDevcontainer.vscode;
        vscodeExtensions = [
          pkgsDevcontainer.vscode-extensions.ms-vscode-remote.remote-containers
        ]
        ++ lib.optionals (lib.elem "vscodevim.vim" cfg.settings.customizations.vscode.extensions) [
          pkgsDevcontainer.vscode-extensions.vscodevim.vim
        ];
      })
    ];
}
