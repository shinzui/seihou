{ name = "multi-instance-helper"
, version = Some "1.0.0"
, description = Some "Helper that writes a skill-named file; instantiated once per distinct skill.name binding"
, vars =
  [ { name = "skill.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the skill being symlinked"
    , required = True
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "template"
    , src = "skill.txt"
    , dest = "out/{{skill.name}}.txt"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
