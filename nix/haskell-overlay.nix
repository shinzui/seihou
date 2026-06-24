{ pkgs
, gitRev
, seihou-schema-src ? null
, okf-src ? null
, baikai-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck;
in
final: prev:
let
  baikaiPackage = name: subdir:
    pkgs.haskell.lib.compose.overrideCabal
      (drv: {
        prePatch = (drv.prePatch or "") + ''
          rm -f LICENSE CHANGELOG.md
          cp ${baikai-src}/LICENSE LICENSE
          cp ${baikai-src}/CHANGELOG.md CHANGELOG.md
        '';
      })
      (doJailbreak (final.callCabal2nix name (baikai-src + "/${subdir}") { }));
in
{
  baikai = baikaiPackage "baikai" "baikai";

  baikai-claude = baikaiPackage "baikai-claude" "baikai-claude";

  baikai-openai = baikaiPackage "baikai-openai" "baikai-openai";

  baikai-kit = baikaiPackage "baikai-kit" "baikai-kit";

  # OKF core library, built from the pinned okf-src flake input's okf-core/
  # subdirectory. Consumed by the seihou-okf-extension package.
  #
  # callCabal2nix copies only okf-core/, but the package references files at the
  # okf repo root that are absent in the staged subdir: ../CHANGELOG.md
  # (extra-doc-files) and ../LICENSE (license-file). Stage them from okf-src in
  # prePatch (mirroring how seihou-core stages ../schema), and dontCheck since we
  # only need the library.
  okf-core = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      prePatch = (drv.prePatch or "") + ''
        cp ${okf-src}/CHANGELOG.md ../CHANGELOG.md
        cp ${okf-src}/LICENSE ../LICENSE
      '';
    })
    (dontCheck (doJailbreak (final.callCabal2nix "okf-core" (okf-src + "/okf-core") { })));

  seihou-core = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      # callCabal2nix only copies seihou-core/, so make the schema submodule
      # available at ../schema during the build for test Dhall imports.
      prePatch = (drv.prePatch or "") + (
        if seihou-schema-src != null then ''
          cp -r ${seihou-schema-src} ../schema
        '' else ""
      );
    })
    (doJailbreak (final.callCabal2nix "seihou-core" ../seihou-core { }));

  seihou-cli = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      configureFlags = (drv.configureFlags or [ ]) ++ [
        "--ghc-option=-DGIT_HASH=\"${builtins.substring 0 7 gitRev}\""
      ];
      # callCabal2nix only copies seihou-cli/, so make the schema submodule
      # available at ../schema during the build for any embedDir/embedFile refs.
      prePatch = (drv.prePatch or "") + (
        if seihou-schema-src != null then ''
          cp -r ${seihou-schema-src} ../schema
        '' else ""
      );
      # Migrate fetch-path tests (MigrateSpec) shell out to `git` to set up
      # fixture remotes; make it available inside the nix sandbox.
      testToolDepends = (drv.testToolDepends or [ ]) ++ [ pkgs.git ];
    })
    (doJailbreak (final.callCabal2nix "seihou-cli" ../seihou-cli { }));

  seihou-okf-extension =
    doJailbreak (final.callCabal2nix "seihou-okf-extension" ../seihou-okf-extension { });
}
