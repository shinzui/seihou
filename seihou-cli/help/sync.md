SYNC — LOCAL LINKS FOR THIS CHECKOUT

At the Git working-tree root:

  seihou sync

Existing declarations restore offline: missing links are created, wrong targets
are repaired, and correct links are left alone. No installed producers are needed.
Tracked files and the manifest remain unchanged during restoration.

OLDER PROJECTS

The same command checks recorded producer sources when the project has no link
declarations. It finds the compositions that declare checkout links, reuses saved
inputs, and shows the necessary project changes before asking:

  Apply link setup? [Y/n]

Accept to adopt setup and create links. Commit the resulting manifest, baselines,
source files and any previewed removal of tracked discovery links. Teammates then
receive that commit and run seihou sync. No module names, installation list,
manual index changes, or separate migration command are required. Sync does not
pull or merge Git branches. Unrelated applications are not selected for update.

PREVIEW AND AUTOMATION

  seihou sync --dry-run
  seihou sync --yes
  seihou sync --dry-run --json
  seihou sync --yes --json

Dry-run does not apply setup. JSON alone does not consent to adoption: it reports
an adoption preview with approvalRequired and exits nonzero. --yes explicitly
accepts adoption for automation. Already-recorded links need no confirmation.
Cancellation leaves setup unapplied and exits nonzero.

PROTECTED PATHS

Real files/directories, modified tracked links, unsafe ancestors and missing
sources remain protected. The adoption preview can propose removing an unchanged,
ignored discovery symlink from the Git index while keeping the working link.
That transition uses the update transaction and its rollback/recovery checks.
Ordinary restoration refuses tracked destinations. There is no force override.

See also: seihou help update; seihou sync --help.
