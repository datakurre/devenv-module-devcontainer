{
  description = "devenv module for devcontainer configuration";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Embed the flake's own source URL so init.sh can guess the devenv input URL.
      flakeSourceUrl = self.sourceInfo.url or "";
    in
    {
      apps = forAllSystems (pkgs: {
        default =
          let
            wizard = pkgs.writeShellApplication {
              name = "devenv-init";
              runtimeInputs = [ pkgs.gum pkgs.nixfmt-rfc-style ];
              text = ''
                FLAKE_SOURCE_URL=${nixpkgs.lib.escapeShellArg flakeSourceUrl}
              '' + builtins.readFile ./init.sh;
            };
          in
          {
            type = "app";
            program = "${wizard}/bin/devenv-init";
          };
      });
    };
}
