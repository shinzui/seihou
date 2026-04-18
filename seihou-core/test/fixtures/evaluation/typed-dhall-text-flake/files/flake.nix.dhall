-- Prototype B: typed-function variant of the flake generator.
-- Called from Seihou.Engine.TypedDhallText.renderTypedDhallText.
-- See docs/plans/8-evaluate-dhall-as-templating-language.md
--
-- This is a Dhall function that takes a typed record and returns Text.
-- No Seihou placeholder substitution happens on this file: the caller
-- builds the record from the resolved VarValue map and applies it.
--
-- The same Nix/Dhall escaping rules as Prototype A apply:
--   ''${...} emits a literal ${...} for Nix interpolation.
--   '''      emits a literal '' for Nix multi-line delimiters.
-- Multi-line strings strip common leading whitespace, so the postgres
-- block is built via concatenation of ordinary "..." strings.
\(vars :
    { project_name         : Text
    , project_description  : Text
    , ghc_version          : Text
    , nix_process_compose  : Bool
    , nix_postgresql       : Bool
    }
  ) ->
let postgresPkg : Text =
      if    vars.nix_postgresql
      then  "            pkgs.postgresql\n"
      else  ""

let postgresShellHook : Text =
      if    vars.nix_postgresql
      then
              "\n"
          ++  "            export PGHOST=\"$PWD/db\"\n"
          ++  "            export PGDATA=\"$PGHOST/db\"\n"
          ++  "            export PGLOG=$PGHOST/postgres.log\n"
          ++  "            export PGDATABASE=${vars.project_name}\n"
          ++  "            export PG_CONNECTION_STRING=postgresql://$(jq -rn --arg x $PGHOST '$x|@uri')/$PGDATABASE\n"
          ++  "\n"
          ++  "            mkdir -p $PGHOST\n"
          ++  "            mkdir -p .dev\n"
          ++  "\n"
          ++  "            if [ ! -d $PGDATA ]; then\n"
          ++  "              initdb --auth=trust --no-locale --encoding=UTF8\n"
          ++  "            fi\n"
      else  ""

let procComposeToggle : Text =
      if    vars.nix_process_compose
      then  "true"
      else  "false"

in  ''
{
  description = "${vars.project_description}";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.pre-commit-hooks.url = "github:cachix/git-hooks.nix";

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, pre-commit-hooks }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskell.packages."${vars.ghc_version}";
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        formatter = treefmtEval.config.build.wrapper;
      in
      {
        formatter = formatter;

        packages = {
          default = haskellPackages.${vars.project_name};
        };

        checks = {
          formatting = treefmtEval.config.build.check self;
          pre-commit-check = pre-commit-hooks.lib.''${system}.run {
            src = ./.;
            hooks = {
              treefmt.package = formatter;
              treefmt.enable = true;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.zlib
            pkgs.just
            pkgs.cabal-install
            pkgs.pkg-config
${postgresPkg}            (haskellPackages.ghcWithPackages (ps: [
              ps.haskell-language-server
            ]))
          ]
          ++ pkgs.lib.optional ${procComposeToggle} pkgs.process-compose;

          shellHook = '''
            ''${self.checks.''${system}.pre-commit-check.shellHook}
            export LANG=en_US.UTF-8
${postgresShellHook}          ''';
        };
      }
    );
}
''
