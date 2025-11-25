{
  description = "A variety of Go versions, packaged for Nix";

  # Flake inputs
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Stable Nixpkgs (use 0.1 for unstable)

  # Auto-configure Garnix cache
  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
  };

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

      lib = inputs.nixpkgs.lib;

      normalizeVersion = version: builtins.replaceStrings [ "go" ] [ "" ] version;
      sourceFiles = files: builtins.filter ({ kind, ... }: kind == "source") files;
      goJson = builtins.filter ({ files, ... }: builtins.length (sourceFiles files) == 1) (
        builtins.fromJSON (builtins.readFile ./go.json)
      );
      sourcesFromGo =
        goJson:
        builtins.map (
          {
            version,
            stable,
            files,
            ...
          }:
          {
            inherit version stable;
            source = builtins.elemAt (sourceFiles files) 0;
          }
        ) goJson;
      goSources = sourcesFromGo goJson;
      majorVersions = [
        "1.25"
        "1.24"
        "1.23"
        "1.22"
        "1.21"
        "1.20"
        "1.19"
        "1.18"
        "1.17"
        "1.16"
        "1.15"
        "1.14"
      ];
      minorsForMajor =
        major:
        builtins.filter (
          { version, stable, ... }: stable && (lib.strings.hasPrefix "go${major}" version)
        ) goSources;
      majorVersionSources =
        (builtins.map (major: builtins.elemAt (minorsForMajor major) 0) majorVersions)
        ++ (minorsForMajor (builtins.elemAt majorVersions 0));

      goPackages =
        goSources:
        forEachSupportedSystem (
          { pkgs, system }:
          builtins.listToAttrs (
            builtins.map (
              { version, source, ... }:
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
      checks = goPackages majorVersionSources;

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
