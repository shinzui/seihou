--| Bug-report profile for defects raised against seihou by the projects that consume it.
-- Bump the tag and semantic hash together when upgrading.
let Profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.15.0/package.dhall
        sha256:e1e7eaac9d08fd3409fe0d19057dba5634a4186733ccbf28323e9aa2a2512dc0

in  Profiles.coordination.bugReports
