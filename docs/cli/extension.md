# `seihou extension`

`seihou extension run NAME -- ARGS...` runs an external extension executable and forwards
the arguments after `--` unchanged.

Extension executables are resolved on `PATH` using the name
`seihou-<NAME>-extension`. For example, the OKF documentation extension is named
`seihou-okf-extension`, so these two forms are equivalent when the executable is on `PATH`:

```bash
seihou extension run okf -- --help
seihou-okf-extension --help
```

The extension process owns its own help text, arguments, stdout, and stderr. If the
executable cannot be found, `seihou` reports the missing executable name and exits non-zero.
If the extension exits non-zero, `seihou` exits with the same status.

The first extension package in this repository is `seihou-okf-extension`. Its `docs`
command is intentionally a placeholder until the OKF registry loader and renderer plans are
implemented.
