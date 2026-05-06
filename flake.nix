{
  description = "devenv module for devcontainer configuration";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      apps = forAllSystems (pkgs: {
        default =
          let
            wizard = pkgs.writeShellApplication {
              name = "devenv-init";
              runtimeInputs = [ pkgs.gum ];
              text = builtins.readFile ./init.sh;
            };
          in
          {
            type = "app";
            program = "${wizard}/bin/devenv-init";
          };
      });
    };
}
