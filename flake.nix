{
  description = "A variety of Go versions, packaged for Nix";

  # Flake inputs
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Stable Nixpkgs (use 0.1 for unstable)

  # Flake outputs
  outputs =
    { self, ... }@inputs:
    let
      # The systems supported for this flake's outputs
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      # Helper for providing system-specific attributes
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            # Provides a system-specific, configured Nixpkgs
            pkgs = import inputs.nixpkgs {
              inherit system;
              # Enable using unfree packages
              config.allowUnfree = true;
            };
          }
        );

      normalizeVersion = version: builtins.replaceStrings [ "go" ] [ "" ] version;
      sourceFiles = files: builtins.filter ({ kind, ... }: kind == "source") files;
      goJson = builtins.filter ({ files, ... }: builtins.length (sourceFiles files) == 1) (builtins.fromJSON (builtins.readFile ./go.json));
      sourcesFromGo = goJson: builtins.map (
        { version, files, ... }:
        {
          inherit version;
          source = builtins.elemAt (sourceFiles files) 0;
        }
      ) goJson;
      goSources = sourcesFromGo goJson;
      recentGoJson = builtins.filter ({ version, stable, ... }: stable && (builtins.compareVersions version "1.24" >= 0)) goJson;
      recentGoSources = sourcesFromGo recentGoJson;

      goPackages = goSources: forEachSupportedSystem (
        { pkgs, system }:
        builtins.listToAttrs (
          builtins.map (
            { version, source }:
            {
              name = builtins.replaceStrings [ "go" "." ] [ "go-" "-" ] version;
              value = pkgs.callPackage ./go.nix {
                inherit version source;
                inherit (inputs) nixpkgs;
              };
            }
          ) goSources
        )
      );
    in
    {
      packages = goPackages goSources;
      checks = goPackages recentGoSources;

      # Nix formatter

      # This applies the formatter that follows RFC 166, which defines a standard format:
      # https://github.com/NixOS/rfcs/pull/166

      # To format all Nix files:
      # git ls-files -z '*.nix' | xargs -0 -r nix fmt
      # To check formatting:
      # git ls-files -z '*.nix' | xargs -0 -r nix develop --command nixfmt --check
      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
