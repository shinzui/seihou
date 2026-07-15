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
  # The 0.3.1.0 Hackage sdist omits data/models and
  # test/fixtures/models-dev-sample.json, which ten upstream tests require.
  # Keep building the library from Hackage while skipping that broken suite.
  baikai = dontCheck (hackagePackage "baikai" "0.3.1.0"
    "sha256-xcyjJt0+YwlXhxXclAayaJh6i7AFvDGTZRPOgUURXBc=");

  baikai-claude = hackagePackage "baikai-claude" "0.3.0.1"
    "sha256-77bDSzeGfYlnKDmjHwpNaXezqOSgQUbO26hDoGYyP8w=";

  baikai-openai = hackagePackage "baikai-openai" "0.3.0.1"
    "sha256-meDqBNMvjlhTWFHVji0yJmg1381bB6HwQdo3SfWLm/w=";

  # The 0.1.0.2 Hackage sdist omits all three test/fixtures/*.json files.
  baikai-kit = dontCheck (hackagePackage "baikai-kit" "0.1.0.2"
    "sha256-kt+CMLJrn1No/reIPwLP6d8hpaxT5O940tGZfQacXNg=");

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
