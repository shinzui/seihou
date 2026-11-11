-- An example judgement that is not about secrets: two checks, one enforced
-- with strict thresholds and one advisory whose concern is a no answer.
-- Evaluated on claude-cli/claude-sonnet-5 against examples.json: 3/3 and 1/1
-- correct. Copy this directory to .seihou/modules/ to use it.
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/9080a472d739456b429455c4da167ed8ee36b483/package.dhall
        sha256:251d9e01c4b2987d5d57e8b38d98e97bd0f6216f280ce3418e3e1759a8755532
in  S.Judgement::{
    , name = "customer-data-review"
    , version = Some "1.0.0"
    , instructions =
        ''
        Review fixtures, logs, and documentation. Synthetic examples are acceptable:
        obviously fake names (Jane Doe, Alice Example), example.com addresses and
        555 phone numbers. Real customer records are not.
        ''
    , evidence = S.JudgementEvidence::{ exclude = [ "*.lock" ] }
    , checks =
      [ S.Check::{
        , name = "real-customer-data"
        , question = "Does this change add information about a real customer?"
        , categories = [ S.FindingCategory::{ name = "customer-record", severity = S.Severity.High } ]
        , blockAt = 0.5
        , passAt = 0.1
        }
      , S.Check::{
        , name = "undocumented-export"
        , question = "Do the privacy notes mention every data export this change adds?"
        , concernWhen = S.Answer.No
        , enforcement = S.Enforcement.Advisory
        , categories = [ S.FindingCategory::{ name = "undocumented-export", severity = S.Severity.Medium } ]
        , blockAt = 0.8
        , passAt = 0.4
        }
      ]
    }
