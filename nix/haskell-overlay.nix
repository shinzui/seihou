{ pkgs
, gitRev
, seihou-schema-src ? null
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck dontHaddock;

  # Packaged Darwin ps has no privileged thread details in the sandbox. Print
  # an explicit unknown state instead of a blank column; keep the existing
  # stopped/zombie cases so process-group cleanup retains its guarantees.
  processTools =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.darwin.ps.overrideAttrs
        (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace ps/print.c \
              --replace-fail '*cp = mach_state_table[k->state];' "*cp = k->state == 0 ? '?' : mach_state_table[k->state];"
          '';
        })
    else pkgs.procps;
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
  # Keep the published releases of mori://shinzui/baikai aligned with the
  # Cabal bounds, independently of the older shared registry source pin.
  baikai = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      # mori://shinzui/baikai/packages/baikai 0.8.0.0 hardcodes /bin/ps.
      # Declare the runtime tool for Linux and sandbox-compatible Darwin builds.
      postPatch = (drv.postPatch or "") + ''
        substituteInPlace src/Baikai/Provider/Cli/Process/Internal.hs \
          --replace-fail 'P.proc "/bin/ps"' 'P.proc "${processTools}/bin/ps"'
      '';
    })
    (dontCheck (hackagePackage "baikai" "0.8.0.0"
      "1ymsin43khbq1bmnp70mgwmfclvz0diy0bji2q3rgwv7m598kmpn"));
  baikai-claude = dontCheck (hackagePackage "baikai-claude" "0.7.1.1"
    "1z6x0aad1cljwscjwxz45lzjjkbcxa7v6vckdshnkv3sqyl93ak4");
  baikai-openai = dontCheck (hackagePackage "baikai-openai" "0.7.1.1"
    "0syv4a7by9grd9bxc9q2vimi4canmaa1x255rqfsqin9jip78n0r");
  baikai-kit = dontCheck (hackagePackage "baikai-kit" "0.4.0.1"
    "037fwpq4h8xdls0svv50sp0v8daa7hcf2axvly9rj9mz6kzlskq4");

  # effectful-core 2.7.x: the ghc9124 package set still carries 2.6.1.0, which
  # is below the `>=2.7.1.1` bound seihou-core/seihou-cli declare (2.7.0.0 has a
  # dynamic-dispatch performance regression, fixed in 2.7.1.1). 2.7 requires
  # strict-mutable-base >= 2, whose API dropped the ticks from the strict
  # MVar/Chan/IORef names, so the set's 1.1.0.0 will not do -- it is pinned
  # alongside. `effectful` is bumped in lockstep even though nothing here
  # depends on it: it is the other consumer of strict-mutable-base in the scope,
  # and leaving 2.6.1.0 against the new base would put a package that cannot
  # build into the set.
  strict-mutable-base = hackagePackage "strict-mutable-base" "2.0.0.0"
    "sha256-3o2PMN8l56X7ULqyNNJrJQZ8xgqqOsxhjm0jfULQt+k=";

  effectful-core = hackagePackage "effectful-core" "2.7.1.2"
    "sha256-OZhGk0UY3BMWF+oUAQnCvF3hnzscBCm0Cz+nz8p2XM8=";

  # 2.7.1.0 is the newest `effectful`; the wrapper is versioned independently
  # of effectful-core and has not been re-released for core's 2.7.1.1/.2. Its
  # `effectful-core < 2.7.2.0` bound admits 2.7.1.2 as-is.
  effectful = hackagePackage "effectful" "2.7.1.0"
    "sha256-1jr7uWldG/qzNljv41c8ustRFNLnD9DuOFBmL3BYT6g=";

  # The shared scope advances Hspec to 2.11.18 while nixpkgs still carries
  # hspec-api 2.11.17, whose exact core bound prevents native package tests.
  # Keep the API package on the same verified upstream release as its peers.
  hspec-api = final.callHackageDirect
    {
      pkg = "hspec-api";
      ver = "2.11.18";
      sha256 = "sha256-dFyNwoEuZfIYZ5xjYYEakjzYYVv5Cjd8rhISsMB41vk=";
    }
    { };

  # tasty-hspec 1.2.0.4 (current Hackage revision 8) caps QuickCheck at
  # 2.17; this scope uses 2.18. Its adapter passes args between Hspec and
  # tasty-quickcheck, both built against that same scope. Keep package tests
  # enabled and verify the bound relaxation with the complete native suites.
  tasty-hspec = doJailbreak prev.tasty-hspec;

  # mori://shinzui/okf/packages/okf-core is supplied by the shared registry.

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
          chmod u+w ../schema
          printf '%s\n' '${seihou-schema-src.rev}' > ../schema/.seihou-pinned-revision
        '' else ""
      );
      # Integration tests use git remotes and Python-owned provider processes.
      testToolDepends = (drv.testToolDepends or [ ]) ++ [ pkgs.git pkgs.python3 ];
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
