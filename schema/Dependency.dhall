-- | Module dependency with optional variable bindings.
--
-- Required fields (no default): module
-- Usage: Dependency::{ module = "nix-base" }
-- With vars: Dependency::{ module = "base", vars = [{ name = "x", value = "y" }] }

{ Type =
    { module : Text
    , vars : List { name : Text, value : Text }
    }
, default =
    { vars = [] : List { name : Text, value : Text }
    }
}
