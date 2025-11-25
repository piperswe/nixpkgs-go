{
  lib,
  stdenv,
  fetchurl,
  tzdata,
  replaceVars,
  iana-etc,
  mailcap,
  buildPackages,
  pkgsBuildTarget,
  threadsCross ? null,
  testers,
  skopeo,
  buildGo124Module,

  go,

  nixpkgs,
  version,
  source,
}:

let
  nixpkgsGoDir = "${nixpkgs}/pkgs/development/compilers/go";
  # We need a target compiler which is still runnable at build time,
  # to handle the cross-building case where build != host == target
  targetCC = pkgsBuildTarget.targetPackages.stdenv.cc;

  isCross = stdenv.buildPlatform != stdenv.targetPlatform;

  finalVersion = builtins.replaceStrings [ "go" ] [ "" ] version;

  atLeast = ver: builtins.compareVersions finalVersion ver >= 0;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "go";
  version = finalVersion;

  src = fetchurl {
    url = "https://go.dev/dl/${source.filename}";
    sha256 = source.sha256;
  };

  strictDeps = true;
  buildInputs =
    [ ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.libc.out ]
    ++ lib.optionals (stdenv.hostPlatform.libc == "glibc") [ stdenv.cc.libc.static ];

  depsBuildTarget = lib.optional isCross targetCC;

  depsTargetTarget = lib.optional stdenv.targetPlatform.isWindows threadsCross.package;

  patches =
    (
      if atLeast "1.11" then
        [ ./patches/remove-tools-1.11.patch ]
      else if atLeast "1.9" then
        [ ./patches/remove-tools-1.9.patch ]
      else if atLeast "1.4" then
        [ ./patches/remove-tools-1.4.patch ]
      else
        [ ]
    )
    ++ (
      if atLeast "1.23" then
        [ ./patches/go_no_vendor_checks-1.22.patch ]
      else if atLeast "1.22" then
        [ ./patches/go_no_vendor_checks-1.22.patch ]
      else if atLeast "1.21" then
        [ ./patches/go_no_vendor_checks-1.21.patch ]
      else if atLeast "1.16" then
        [ ./patches/go_no_vendor_checks-1.16.patch ]
      else if atLeast "1.14" then
        [ ./patches/go_no_vendor_checks-1.14.patch ]
      else
        [ ]
    );

  postPatch = ''
    sed -i 's@"/etc/protocols"@"${iana-etc}/etc/protocols"@g' src/net/lookup_unix.go
    sed -i 's@"/etc/protocols"@"${iana-etc}/etc/services"@g' src/net/port_unix.go
    sed -i 's@"/etc/mime.types"@"${mailcap}/etc/mime.types","/etc/mime.types"@g' src/mime/type_unix.go
    sed -i 's@"/usr/share/zoneinfo/"@"${tzdata}/share/zoneinfo/","/usr/share/zoneinfo/"@g' src/time/zoneinfo_unix.go

    patchShebangs .
  '';

  inherit (stdenv.targetPlatform.go) GOOS GOARCH GOARM;
  # GOHOSTOS/GOHOSTARCH must match the building system, not the host system.
  # Go will nevertheless build a for host system that we will copy over in
  # the install phase.
  GOHOSTOS = stdenv.buildPlatform.go.GOOS;
  GOHOSTARCH = stdenv.buildPlatform.go.GOARCH;

  # {CC,CXX}_FOR_TARGET must be only set for cross compilation case as go expect those
  # to be different from CC/CXX
  CC_FOR_TARGET = if isCross then "${targetCC}/bin/${targetCC.targetPrefix}cc" else null;
  CXX_FOR_TARGET = if isCross then "${targetCC}/bin/${targetCC.targetPrefix}c++" else null;

  GO386 = "softfloat"; # from Arch: don't assume sse2 on i686
  # Wasi does not support CGO
  CGO_ENABLED = if stdenv.targetPlatform.isWasi then 0 else 1;

  GOROOT_BOOTSTRAP = "${go}/share/go";

  buildPhase = ''
    runHook preBuild
    export GOCACHE=$TMPDIR/go-cache

    export PATH=$(pwd)/bin:$PATH

    ${lib.optionalString isCross ''
      # Independent from host/target, CC should produce code for the building system.
      # We only set it when cross-compiling.
      export CC=${buildPackages.stdenv.cc}/bin/cc
    ''}
    ulimit -a

    pushd src
    ./make.bash
    popd
    runHook postBuild
  '';

  preInstall = ''
    # Contains the wrong perl shebang when cross compiling,
    # since it is not used for anything we can deleted as well.
    rm src/regexp/syntax/make_perl_groups.pl
  ''
  + (
    if (stdenv.buildPlatform.system != stdenv.hostPlatform.system) then
      ''
        mv bin/*_*/* bin
        rmdir bin/*_*
        ${lib.optionalString
          (!(finalAttrs.GOHOSTARCH == finalAttrs.GOARCH && finalAttrs.GOOS == finalAttrs.GOHOSTOS))
          ''
            rm -rf pkg/${finalAttrs.GOHOSTOS}_${finalAttrs.GOHOSTARCH} pkg/tool/${finalAttrs.GOHOSTOS}_${finalAttrs.GOHOSTARCH}
          ''
        }
      ''
    else
      lib.optionalString (stdenv.hostPlatform.system != stdenv.targetPlatform.system) ''
        rm -rf bin/*_*
        ${lib.optionalString
          (!(finalAttrs.GOHOSTARCH == finalAttrs.GOARCH && finalAttrs.GOOS == finalAttrs.GOHOSTOS))
          ''
            rm -rf pkg/${finalAttrs.GOOS}_${finalAttrs.GOARCH} pkg/tool/${finalAttrs.GOOS}_${finalAttrs.GOARCH}
          ''
        }
      ''
  );

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/go
    cp -a bin pkg src lib misc api doc VERSION $out/share/go
    if [[ -f go.env ]]; then cp -a go.env $out/share/go/; fi
    mkdir -p $out/bin
    ln -s $out/share/go/bin/* $out/bin
    runHook postInstall
  '';

  disallowedReferences = [ go ];

  passthru = {
    tests = {
      version = testers.testVersion {
        package = finalAttrs.finalPackage;
        command = "go version";
        version = "go${finalAttrs.version}";
      };
    };
  };

  meta = with lib; {
    changelog = "https://go.dev/doc/devel/release#go${lib.versions.majorMinor finalAttrs.version}";
    description = "Go Programming language";
    homepage = "https://go.dev/";
    license = licenses.bsd3;
    maintainers = [ maintainers.piperswe ];
    platforms = platforms.darwin ++ platforms.linux ++ platforms.wasi ++ platforms.freebsd;
    mainProgram = "go";
  };
})
