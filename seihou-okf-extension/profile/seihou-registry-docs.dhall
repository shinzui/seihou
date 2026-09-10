--| House profile for an OKF documentation bundle generated from a Seihou registry.
--
-- A profile is a house convention, not part of the OKF standard: a bundle that
-- deviates from this descriptor is still fully OKF-conformant. What this one
-- says is what `seihou-okf-extension docs` promises about the bundles it emits,
-- so that a consumer can check a bundle it did not generate itself.
--
-- `pathPattern` is matched against a concept ID (`modules/haskell-library`),
-- not a file path, so it carries no `.md` suffix; `*` matches exactly one
-- segment.
--
-- The descriptor is deliberately standalone -- every type is spelled out here
-- rather than imported -- because it is embedded in the generator and written
-- into the bundle root, where a relative import out of the bundle would not
-- resolve.
let Cardinality = < Any | Scalar | List >

let FieldFormat =
      < Rfc3339Utc
      | Date
      | Uri
      | UriWithScheme : Text
      | DocumentHandle : Text
      | Actor
      | HumanActor
      | Integer
      | NonNegativeInteger
      | Boolean
      >

let FieldCondition = { field : Text, hasValue : List Text }

let HandleReferenceRule =
      { localPrefix : Text
      , externalUriSchemes : List Text
      , allowSelf : Bool
      , allowLocal : Bool
      , externalUriPattern : Optional Text
      }

let PathReferenceRule = { externalUriSchemes : List Text, allowSelf : Bool }

let NestedFieldRule =
      { field : Text
      , description : Optional Text
      , allowedValues : List Text
      , cardinality : Cardinality
      , format : Optional FieldFormat
      , path : Optional PathReferenceRule
      , when : Optional FieldCondition
      , reference : Optional HandleReferenceRule
      }

let NestedRules =
      { required : List NestedFieldRule
      , recommended : List NestedFieldRule
      , optional : List NestedFieldRule
      }

let FieldRule =
      { field : Text
      , description : Optional Text
      , allowedValues : List Text
      , cardinality : Cardinality
      , format : Optional FieldFormat
      , elementFields : Optional NestedRules
      , objectFields : Optional NestedRules
      , reference : Optional HandleReferenceRule
      , path : Optional PathReferenceRule
      , when : Optional FieldCondition
      , uniqueBy : Optional Text
      }

let FrontmatterRules =
      { required : List FieldRule
      , recommended : List FieldRule
      , optional : List FieldRule
      }

let TypeRule =
      { type : Text
      , description : Optional Text
      , frontmatter : FrontmatterRules
      , pathPattern : Optional Text
      , resourceScheme : Optional Text
      , requireSchemaSection : Bool
      , schemaColumns : List Text
      , idPrefix : Optional Text
      }

let emptyRules
    : FrontmatterRules
    = { required = [] : List FieldRule
      , recommended = [] : List FieldRule
      , optional = [] : List FieldRule
      }

let nestedScalar =
      \(name : Text) ->
      \(description : Text) ->
        { field = name
        , description = Some description
        , allowedValues = [] : List Text
        , cardinality = Cardinality.Scalar
        , format = None FieldFormat
        , path = None PathReferenceRule
        , when = None FieldCondition
        , reference = None HandleReferenceRule
        }

let field =
      \(name : Text) ->
      \(description : Text) ->
      \(cardinality : Cardinality) ->
      \(format : Optional FieldFormat) ->
      \(objectFields : Optional NestedRules) ->
        { field = name
        , description = Some description
        , allowedValues = [] : List Text
        , cardinality
        , format
        , elementFields = None NestedRules
        , objectFields
        , reference = None HandleReferenceRule
        , path = None PathReferenceRule
        , when = None FieldCondition
        , uniqueBy = None Text
        }

let scalar =
      \(name : Text) ->
      \(description : Text) ->
        field name description Cardinality.Scalar (None FieldFormat) (None NestedRules)

let versionRule =
      scalar
        "version"
        "The version the registry catalog records for this artifact. Optional rather than required, because `seihou-registry.dhall` itself declares `version : Optional Text`; a profile that demanded it would refuse a valid registry."

let artifactType =
      \(name : Text) ->
      \(description : Text) ->
      \(directory : Text) ->
        { type = name
        , description = Some description
        , frontmatter = emptyRules // { optional = [ versionRule ] }
        , pathPattern = Some "${directory}/*"
        , resourceScheme = Some "seihou"
        , requireSchemaSection = False
        , schemaColumns = [] : List Text
        , idPrefix = None Text
        }

in  { name = "seihou-registry-docs"
    , description = Some
        "Generated documentation for a Seihou registry: one concept per published module, recipe, blueprint and agent prompt, plus one describing the registry itself. Every concept names the registry artifact it was derived from through a `seihou://` resource and records the generator that produced it, so a reader can tell derived documentation from hand-written prose and can find the `.dhall` source it came from."
    , okfVersion = "0.2"
    , frontmatter =
            emptyRules
        //  { required =
              [ scalar "type" "Which kind of Seihou artifact this concept documents."
              , scalar "title" "The artifact's name, exactly as the registry publishes it."
              , scalar
                  "description"
                  "What the artifact is for. Taken from the registry catalog entry, else the artifact's own description, else synthesized."
              , field
                  "resource"
                  "A `seihou://<registry>/<path>` pointer to the artifact this concept was derived from."
                  Cardinality.Scalar
                  (Some (FieldFormat.UriWithScheme "seihou"))
                  (None NestedRules)
              , field
                  "generated"
                  "Which producer generated this concept, per OKF specification section 5.2. Always present, because this documentation is derived rather than written."
                  Cardinality.Any
                  (None FieldFormat)
                  ( Some
                      (     emptyRules
                        //  { required =
                              [     nestedScalar
                                      "by"
                                      "The producer actor, `seihou-okf-extension/<version>`."
                                //  { format = Some FieldFormat.Actor }
                              ]
                            , optional =
                              [ nestedScalar
                                  "at"
                                  "The generation time, present only when the operator passed --generated-at."
                              ]
                            , recommended = [] : List NestedFieldRule
                            }
                      )
                  )
              ]
            , recommended =
              [ field
                  "tags"
                  "The tags the registry catalog records for this artifact."
                  Cardinality.List
                  (None FieldFormat)
                  (None NestedRules)
              ]
            , optional =
              [ field
                  "status"
                  "The concept's lifecycle status, per OKF specification section 5.4."
                  Cardinality.Scalar
                  (None FieldFormat)
                  (None NestedRules)
              ]
            }
    , allowUnknownTypes = False
    , allowUnknownFields = True
    , idField = None Text
    , requireBundleVersion = Some "0.2"
    , types =
      [ artifactType
          "SeihouModule"
          "A deterministic file-generation template: variables, generation steps, shell commands, dependencies, an optional removal procedure and optional migration edges."
          "modules"
      , artifactType
          "SeihouRecipe"
          "A named composition of modules with preset variable bindings."
          "recipes"
      , artifactType
          "SeihouBlueprint"
          "An agent-driven scaffold: a prompt, optional base modules, reference files and optional agent-guided migration edges."
          "blueprints"
      , artifactType
          "SeihouPrompt"
          "A reusable agent-session template."
          "prompts"
      ,     artifactType
              "SeihouRegistry"
              "The registry itself: the repository publishing these artifacts, linking each of them."
              "registry"
        //  { frontmatter = emptyRules }
      ]
    }
