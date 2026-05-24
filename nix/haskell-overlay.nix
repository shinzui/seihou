{ pkgs
, gitRev
, seihou-schema-src ? null
, baikai-src ? null
, claude-src ? null
, openai-src ? null
, cradle-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak;
  stageBaikaiRootFiles = drv: {
    prePatch = (drv.prePatch or "") + ''
      cp ${baikai-src}/CHANGELOG.md ../CHANGELOG.md
      cp ${baikai-src}/LICENSE ../LICENSE
    '';
  };
in
final: prev: {
  wai-app-static = pkgs.haskell.lib.compose.dontCheck (doJailbreak (final.callHackageDirect
    {
      pkg = "wai-app-static";
      ver = "3.1.9.1";
      sha256 = "1irlknakxl7dcwxxdw0iliql7xrbyssz4bdk18amr2xl2d0fcwzc";
    }
    { }));

  cradle = pkgs.haskell.lib.compose.dontCheck (doJailbreak (final.callCabal2nix "cradle" cradle-src { }));

  claude = pkgs.haskell.lib.compose.dontCheck (doJailbreak (final.callCabal2nix "claude" (claude-src + "/claude") { }));

  openai = pkgs.haskell.lib.compose.dontCheck (doJailbreak (final.callCabal2nix "openai" (openai-src + "/openai") { }));

  baikai = pkgs.haskell.lib.compose.dontCheck (
    pkgs.haskell.lib.compose.overrideCabal stageBaikaiRootFiles
      (doJailbreak (final.callCabal2nix "baikai" (baikai-src + "/baikai") { }))
  );

  baikai-claude = pkgs.haskell.lib.compose.dontCheck (
    pkgs.haskell.lib.compose.overrideCabal stageBaikaiRootFiles
      (doJailbreak (final.callCabal2nix "baikai-claude" (baikai-src + "/baikai-claude") { }))
  );

  baikai-openai = pkgs.haskell.lib.compose.dontCheck (
    pkgs.haskell.lib.compose.overrideCabal stageBaikaiRootFiles
      (doJailbreak (final.callCabal2nix "baikai-openai" (baikai-src + "/baikai-openai") { }))
  );

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
}
