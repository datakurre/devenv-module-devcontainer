{ pkgs, ... }:
let
  shell =
    { pkgs, ... }:
    {
      services.postgres.enable = true;
      services.postgres.initialDatabases = [
        {
          name = "vasara-engine";
        }
      ];
      services.postgres.listen_addresses = "localhost";
      services.postgres.initialScript = ''
        CREATE USER "vasara-engine" WITH LOGIN PASSWORD 'vasara-engine';
        ALTER DATABASE "vasara-engine" OWNER TO "vasara-engine";
      '';
      services.redis.enable = true;
      services.redis.extraConfig = ''
        requirepass vasara-engine
      '';
      services.keycloak.enable = true;
      services.keycloak.realms.vasara = {
        path = "./fixtures/vasara-realm.json";
        import = true;
        export = true;
      };

      packages = [
        pkgs.gnumake
        pkgs.google-java-format
        pkgs.nixfmt-rfc-style
        pkgs.nodejs
        pkgs.nodejs
        pkgs.prettier
        pkgs.python3
        pkgs.treefmt
        pkgs.xmlformat
      ];

      enterShell = ''
        mvn -version
      '';

      enterTest = ''
        # Run all Maven tests
        mvn test
      '';
    };

  package =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.package.vasara-engine;
      inherit (lib) types mkOption;
    in
    {
      options.package.vasara-engine = {
        jre = mkOption {
          type = types.package;
        };
      };
      config = {
        package.image.path = "vasara-bpm/vasara-engine/vasara-enine";
        package.image.package = config.outputs.vasara-engine.app;
        package.vasara-engine.jre = pkgs.temurin-jre-bin-25;
        outputs.vasara-engine = {
          jar = pkgs.callPackage ./default.jar.nix rec {
            jdk_headless = config.languages.java.jdk.package;
            maven = config.languages.java.maven.package.override { inherit jdk_headless; };
            inherit (config.languages.java.mvn2nix.lib)
              buildMavenRepositoryFromLockFile
              ;
          };
          app = pkgs.callPackage ./default.nix {
            jar = config.outputs.vasara-engine.jar;
            jre = config.package.vasara-engine.jre;
          };
        };
      };
    };
  service =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.package.vasara-engine;
      inherit (lib) types mkOption;
    in
    {
      options.package.vasara-engine = {
        port = mkOption {
          type = types.port;
          default = 8800;
        };
        deployment = mkOption {
          type = types.path;
          default = ./deployment;
        };
      };
      config = {
        processes.vasara-engine.exec = ''
          java $JAVA_OPTS \
            -Dserver.port="${builtins.toString cfg.port}" \
            -Dcamunda.deploymentDir="${cfg.deployment}" \
            -jar "${config.outputs.vasara-engine.jar}"
        '';
      };
    };
in
{
  dotenv.enable = true;

  languages.java.jdk.package = pkgs.jdk21;

  profiles.shell.module = {
    imports = [ shell ];
  };

  profiles.package.module = {
    imports = [ package ];
  };

  profiles.service.module = {
    imports = [
      package
      service
    ];
  };

  profiles.devcontainer.module = {
    devcontainer.enable = true;
    devcontainer.networkMode = "host";
    devcontainer.tweaks = [
      "podman"
      "vscode"
    ];
    devcontainer.settings.customizations.vscode.extensions = [
      "GitHub.copilot"
      "GitHub.copilot-chat"
      "bbenoist.Nix"
      "eamodio.gitlens"
      "mkhl.direnv"
      "ms-vscode.makefile-tools"
      "redhat.java"
      "vscjava.vscode-java-debug"
      "vscjava.vscode-java-test"
      "vscjava.vscode-maven"
      "vscjava.vscode-java-dependency"
      "visualstudioexptteam.vscodeintellicode"
      "vscodevim.vim"
    ];
  };
}
