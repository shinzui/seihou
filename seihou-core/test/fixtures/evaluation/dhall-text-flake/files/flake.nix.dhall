-- Prototype A: single Dhall source that produces both variants of the
-- nix-haskell-flake flake.nix by branching on nixPostgresql.
--
-- See docs/plans/8-evaluate-dhall-as-templating-language.md for context.
--
-- The current DhallText strategy substitutes Seihou placeholders FIRST
-- and then evaluates the result as Dhall. Each binding below receives a
-- concrete Dhall literal after substitution:
--   project.name         -> bare token; must be wrapped in "..." so it
--                           parses as Dhall Text.
--   nix.postgresql       -> bare 'true' or 'false'. Seihou renders Bool
--                           values in lowercase but Dhall Bool literals
--                           are 'True'/'False', so we introduce two shim
--                           bindings to bridge the gap.
--
-- Nix uses ${...} for its own interpolation, which collides with Dhall's
-- ${...} inside ''...'' multi-line strings. In Dhall:
--   ''${...} emits a literal ${...} (for Nix interpolation).
--   '''      emits a literal '' (Nix's multi-line string delimiter).
--
-- Dhall multi-line strings strip the longest common leading-whitespace
-- prefix. Blocks built by concatenation of regular "..." strings avoid
-- that behaviour, so the postgres-specific blocks below use explicit
-- \n rather than multi-line literals.
let true  = True
let false = False

let projectName         = "{{project.name}}"
let projectDescription  = "{{project.description}}"
let ghcVersion          = "{{ghc.version}}"
let nixProcessCompose   = {{nix.process-compose}}
let nixPostgresql       = {{nix.postgresql}}

let postgresPkg : Text =
      if    nixPostgresql
      then  "            pkgs.postgresql\n"
      else  ""

let postgresShellHook : Text =
      if    nixPostgresql
      then
              "\n"
          ++  "            export PGHOST=\"$PWD/db\"\n"
          ++  "            export PGDATA=\"$PGHOST/db\"\n"
          ++  "            export PGLOG=$PGHOST/postgres.log\n"
          ++  "            export PGDATABASE=${projectName}\n"
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
      if    nixProcessCompose
      then  "true"
      else  "false"

in  ''
{
  description = "${projectDescription}";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.pre-commit-hooks.url = "github:cachix/git-hooks.nix";

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, pre-commit-hooks }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskell.packages."${ghcVersion}";
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        formatter = treefmtEval.config.build.wrapper;
      in
      {
        formatter = formatter;

        packages = {
          default = haskellPackages.${projectName};
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
