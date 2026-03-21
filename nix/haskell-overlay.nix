{ pkgs
, gitRev
, seihou-schema-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak;
in
final: prev: {
  seihou-core = doJailbreak (final.callCabal2nix "seihou-core" ../seihou-core { });

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
    })
    (doJailbreak (final.callCabal2nix "seihou-cli" ../seihou-cli { }));
}
