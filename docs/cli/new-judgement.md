# seihou new-judgement

Scaffold a new judgement.

```sh
seihou new-judgement NAME [--path DIR]
```

Creates `.seihou/modules/NAME/judgement.dhall` and `.seihou/modules/NAME/examples.json`,
or the same two files under `--path DIR` when authoring for a registry. It refuses an
existing directory and writes nothing then. Names match `[a-z][a-z0-9-]*`.

The scaffolded `judgement.dhall` imports the schema at the immutable URL and hash
this Seihou release pins, and declares one check whose concern is described in the
`instructions` field. Edit the instructions to say what this project must not commit
and what is acceptable, then replace the placeholder case in `examples.json` with a
synthetic example of the concern.

Next:

```sh
seihou validate-judgement NAME
seihou judgement eval NAME
seihou run NAME
```

See the [judgements guide](../user/judgements.md) for the definition format.
