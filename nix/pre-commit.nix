# git-hooks.nix (pre-commit) as a flake-parts module. The dev shell installs the
# hooks via `config.pre-commit.installationScript` (see ./haskell.nix). Besides
# treefmt, this enforces the CLI library-first module-placement convention via
# ./check-cli-module-placement.sh and the record conventions via
# ./check-record-conventions.sh (both also exposed as standalone flake checks in
# ../flake.module.nix).
{ inputs, ... }:
{
  imports = [ inputs.pre-commit-hooks.flakeModule ];

  perSystem = { config, pkgs, ... }: {
    pre-commit.settings.hooks = {
      treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };

      cli-module-placement = {
        enable = true;
        name = "cli-module-placement";
        entry = "${pkgs.bash}/bin/bash ${./check-cli-module-placement.sh}";
        language = "system";
        pass_filenames = false;
      };

      record-conventions = {
        enable = true;
        name = "record-conventions";
        entry = "${pkgs.bash}/bin/bash ${./check-record-conventions.sh}";
        language = "system";
        pass_filenames = false;
      };
    };
  };
}
