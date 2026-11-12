EXTENSIONS

  seihou extension run NAME -- ARGS...

Seihou locates seihou-NAME-extension on PATH and forwards everything after --
unchanged. The extension owns its options, output and help. If it is absent,
install its executable or put it on PATH. A failing extension's exit status is
returned by Seihou.

OKF DOCUMENTATION

  seihou extension run okf -- --help
  seihou extension run okf -- docs
  seihou extension run okf -- docs --force

  The separately installed seihou-okf-extension generates an Open Knowledge
  Format bundle from a Seihou registry. Its --force option replaces a non-empty
  output directory after validating the replacement. Invalid declarations or a rejecting
  profile preserve existing output. Run from a fresh registry checkout; no artifact
  installation is needed. Covers modules, recipes, blueprints, prompts and judgements.

SEE ALSO

  seihou extension --help
  seihou help registry
