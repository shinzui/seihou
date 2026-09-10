{ pkgs
, gitRev
, seihou-schema-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck dontHaddock;
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
  # source — baikai 0.4.1.0, baikai-claude/openai 0.4.0.0 (which forward
  # Options.thinking to the batch `claude -p` / `codex exec` invocations as a
  # reasoning-effort flag, not just to interactive launches), baikai-kit
  # 0.1.0.3 — already wrapped with dontCheck + doJailbreak.
  # Only okf-core needs a local Hackage pin. The shared overlay does carry an
  # okf-src input, but it sits at okf 0.2.0.0, so it cannot supply the 0.8.0.0
  # release this repository builds against.

  # dontCheck: this repository has no reason to run a dependency's own test
  # suite on every build. (The 0.8.0.0 sdist does ship dhall/ and
  # test/fixtures/, unlike 0.1.2.0, so the old justification no longer
  # applies -- the flag is kept purely for build time.)
  okf-core = dontCheck (hackagePackage "okf-core" "0.8.0.0"
    "sha256-ADugvEouY5r+o1W0K09M7IX0GTVuZ1OXvA+Vem/QnBI=");

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
    (dontHaddock (doJailbreak (final.callCabal2nix "seihou-core" ../seihou-core { })));

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
    (dontHaddock (doJailbreak (final.callCabal2nix "seihou-cli" ../seihou-cli { })));

  # `dontHaddock` below: seihou ships a CLI, not a library anyone reads Haddock
  # for, and these are exactly the derivations that rebuild on every `nix build`
  # here and on every `darwin-rebuild` in mori://shinzui/dotfiles.nix. nixpkgs'
  # builder defaults `doHaddock` to true, which adds a `doc` output plus a
  # Haddock pass over the package and its dependencies' interfaces — pure
  # repeated cost. Scoped to these packages rather than the whole scope (which
  # is what `disableHaddock = true` on mori://shinzui/haskell-nix's
  # `mkChannelExtension` would do) so the dependency closure keeps its hashes
  # instead of needing a one-time full rebuild.

  seihou-okf-extension =
    dontHaddock (doJailbreak (final.callCabal2nix "seihou-okf-extension" ../seihou-okf-extension { }));
}
