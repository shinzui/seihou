-- | Variable declaration within a module.
--
-- Required fields (no default): name, type
-- Usage: VarDecl::{ name = "project.name", type = "text", required = True }

{ Type =
    { name : Text
    , type : Text
    , default : Optional Text
    , description : Optional Text
    , required : Bool
    , validation : Optional Text
    }
, default =
    { default = None Text
    , description = None Text
    , required = False
    , validation = None Text
    }
}
