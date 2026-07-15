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
  # The 0.3.0.0 Hackage sdist omits data/models and
  # test/fixtures/models-dev-sample.json, which ten upstream tests require.
  # Keep building the library from Hackage while skipping that broken suite.
  baikai = dontCheck (hackagePackage "baikai" "0.3.0.0"
    "sha256-VwZp50ty0qEOhhg1dIt5jXI7K6yQd9na7mudNMtMdCQ=");

  baikai-claude = hackagePackage "baikai-claude" "0.3.0.0"
    "sha256-eyMwD7rPXW1+sE0ORrhkoUf73IlJAlVhnWlIPepA8Zc=";

  baikai-openai = hackagePackage "baikai-openai" "0.3.0.0"
    "sha256-BCcLlRduPlqrBQkVa+bd8zufzb9ASr/1SdbI4yS6bjU=";

  # The 0.1.0.1 Hackage sdist omits all three test/fixtures/*.json files.
  baikai-kit = dontCheck (hackagePackage "baikai-kit" "0.1.0.1"
    "sha256-NjBDf2Zx3zafMGAM6a660jlcI3jcd+C2RKJOUniiDIY=");

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
