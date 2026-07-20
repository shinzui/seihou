{ pkgs
, gitRev
, seihou-schema-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck;
in
final: prev:
let
  hackagePackage = name: version: sha256:
    doJailbreak (final.callHackageDirect
      {
        pkg = name;
        ver = version;
        inherit sha256;
      }
      { });
in
{
  # baikai, baikai-claude, baikai-openai, and baikai-kit are supplied by the
  # shared haskell-nix registry overlay (composed ahead of this one in
  # ../flake.module.nix), which builds the whole baikai family from its GitHub
  # source — baikai 0.4.0.0 (reasoning-effort support), baikai-claude/openai
  # 0.3.0.2, baikai-kit 0.1.0.3 — already wrapped with dontCheck + doJailbreak.
  # Only okf-core, which is not registered there, needs a local Hackage pin.

  # The 0.1.2.0 Hackage sdist omits dhall/ and test/fixtures/, which its
  # upstream test suite requires.
  okf-core = dontCheck (hackagePackage "okf-core" "0.1.2.0"
    "sha256-p2LC8DDdqeLnlQn/n8jBL6tt6Iid+bPK15zBRwIOnJg=");

  seihou-core = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      # callCabal2nix only copies seihou-core/, so make the schema submodule
      # available at ../schema during the build for test Dhall imports.
      prePatch = (drv.prePatch or "") + (
        if seihou-schema-src != null then ''
          cp -r ${seihou-schema-src} ../schema
        '' else ""
      );
      # Three-way merge and update-transaction tests shell out to `git`.
      # Make it available inside the Nix test sandbox so pending tests do not
      # cause the suite to fail.
      testToolDepends = (drv.testToolDepends or [ ]) ++ [ pkgs.git ];
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
      # Integration tests shell out to `git` for fixture remotes; make it
      # available inside the Nix test sandbox.
      testToolDepends = (drv.testToolDepends or [ ]) ++ [ pkgs.git ];
    })
    (doJailbreak (final.callCabal2nix "seihou-cli" ../seihou-cli { }));

  seihou-okf-extension =
    doJailbreak (final.callCabal2nix "seihou-okf-extension" ../seihou-okf-extension { });
}
