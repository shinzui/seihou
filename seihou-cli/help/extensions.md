EXTENSIONS

  seihou extension run NAME -- ARGS...

Seihou locates seihou-NAME-extension on PATH and forwards everything after --
unchanged. The extension owns its options, output and help. If it is absent,
install its executable or put it on PATH. A failing extension's exit status is
returned by Seihou.

OKF DOCUMENTATION

  seihou extension run okf -- --help
  seihou extension run okf -- docs --dir . --out okf-docs

  The separately installed seihou-okf-extension generates an Open Knowledge
  Format bundle from a Seihou registry. Its --force option replaces a non-empty
  output directory; inspect its own help before choosing options.

SEE ALSO

  seihou extension --help
  seihou help registry
