-- | Variable export — re-exports a variable for dependent modules.
--
-- Required fields (no default): var
-- Usage: VarExport::{ var = "project.name" }

{ Type = { var : Text, alias : Optional Text }
, default = { alias = None Text }
}
