-- | Shell command to run after file generation.
--
-- Required fields (no default): run
-- Usage: Command::{ run = "echo 'Project generated'" }

{ Type =
    { run : Text
    , workDir : Optional Text
    , when : Optional Text
    }
, default =
    { workDir = None Text
    , when = None Text
    }
}
