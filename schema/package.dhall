-- | Seihou Schema Package
--
-- Import this file to use Dhall record completion (::) for module authoring.
--
-- Example:
--   let S = ./package.dhall
--   in S.Module::{ name = "my-module"
--                , steps = [ S.Step::{ strategy = "template", src = "foo.tpl", dest = "foo" } ]
--                }

{ VarDecl = ./VarDecl.dhall
, VarExport = ./VarExport.dhall
, Prompt = ./Prompt.dhall
, Step = ./Step.dhall
, Command = ./Command.dhall
, Dependency = ./Dependency.dhall
, Module = ./Module.dhall
}
