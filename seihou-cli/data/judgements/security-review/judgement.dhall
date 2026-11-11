-- The bundled security-review judgement.
--
-- This file is self-contained: it imports nothing, so `seihou run
-- security-review` can evaluate it without fetching the schema. It is the
-- normalized form of a Judgement written against mori://shinzui/seihou-schema
-- (package.dhall at the revision pinned in Seihou.CLI.SchemaVersion); edit it
-- as that source and re-normalize with `dhall --file`, or edit it in place
-- and run `cabal test seihou-cli` to check it still decodes and validates.
--
-- Its thresholds are provisional until the release corpus qualifies them on
-- the advertised route.
{ checks =
  [ { blockAt = 0.6
    , blockingSeverity = < Critical | High | Info | Low | Medium >.High
    , categories =
      [ { description = Some "A token, key, password or connection secret."
        , name = "embedded-credential"
        , severity = < Critical | High | Info | Low | Medium >.Critical
        }
      , { description = Some "Private key material."
        , name = "private-key"
        , severity = < Critical | High | Info | Low | Medium >.Critical
        }
      ]
    , concernWhen = < No | Yes >.Yes
    , enforcement = < Advisory | Enforced >.Enforced
    , gateBlockAt = 0.9
    , gatePassAt = 5.0e-2
    , name = "credentials"
    , noMeans = Some
        "Every secret-looking value is a placeholder, a reference, a public key or clearly synthetic test data."
    , passAt = 0.2
    , question =
        "Does this change add a working credential, such as an API key, access token, password or private key?"
    , useGate = True
    , yesMeans = Some
        "At least one shown value would grant access to a system if someone copied it."
    }
  , { blockAt = 0.7
    , blockingSeverity = < Critical | High | Info | Low | Medium >.High
    , categories =
      [ { description = Some "Data about an identifiable real person."
        , name = "personal-data"
        , severity = < Critical | High | Info | Low | Medium >.High
        }
      , { description = Some "A real customer or account record."
        , name = "customer-record"
        , severity = < Critical | High | Info | Low | Medium >.High
        }
      , { description = Some "An internal hostname, address or topology detail."
        , name = "internal-infrastructure"
        , severity = < Critical | High | Info | Low | Medium >.Medium
        }
      , { description = Some
            "Non-public financial, legal or strategic information."
        , name = "confidential-business"
        , severity = < Critical | High | Info | Low | Medium >.High
        }
      ]
    , concernWhen = < No | Yes >.Yes
    , enforcement = < Advisory | Enforced >.Enforced
    , gateBlockAt = 0.9
    , gatePassAt = 5.0e-2
    , name = "confidential-data"
    , noMeans = Some
        "All personal or business data shown is synthetic, public, or a documented example."
    , passAt = 0.3
    , question =
        "Does this change add confidential information, such as personal data about real people, customer records, internal hostnames or non-public business data?"
    , useGate = True
    , yesMeans = Some
        "At least one shown value identifies a real person or customer, or exposes non-public internal information."
    }
  ]
, description = Some
    "Blocks commits that add credentials or confidential information."
, deterministicChecks = [ < SecretScan >.SecretScan ]
, evidence =
  { exclude = [] : List Text
  , include = [] : List Text
  , scopes =
    [ < CommitRange | StagedChanges >.StagedChanges
    , < CommitRange | StagedChanges >.CommitRange
    ]
  }
, instructions =
    ''
    You review a change that is about to be committed to a source repository
    that other people can read. Decide whether the change adds material that
    must not be committed.

    Material that must not be committed includes working credentials (API keys,
    access tokens, passwords, private keys, connection strings with embedded
    passwords, signing secrets) and confidential information (personal data
    about identifiable real people, customer or account records, internal
    hostnames or network addresses that are not meant to be public, and
    non-public business figures or plans).

    Material that is acceptable includes obvious placeholders such as
    "changeme", "<your-token>" or "xxxx", values documented as fake, test
    fixtures that are clearly synthetic, environment-variable names without
    values, references to where a secret is stored, public keys and
    certificates, and example domains such as example.com.

    Judge what the change adds or keeps in the shown files. Removing a secret is
    not a concern. Do not report style, correctness or other unrelated issues.
    ''
, limits =
  { maxAttempts = 3
  , maxChunkBytes = 49152
  , maxChunks = 16
  , maxFileBytes = 262144
  , maxFindings = 20
  , timeoutSeconds = 120
  }
, name = "security-review"
, version = Some "1.0.0"
}
