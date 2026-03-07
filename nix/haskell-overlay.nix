{ pkgs
, gitRev
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
    })
    (doJailbreak (final.callCabal2nix "seihou-cli" ../seihou-cli { }));
}
