# seihou init

Initialize Seihou configuration.

## Usage

```
seihou init
```

## Description

Creates the Seihou configuration directory at `~/.config/seihou/` with subdirectories for user modules and installed modules. Writes a default `config.dhall` file.

Safe to run multiple times — existing files are left untouched.

## Created Structure

```
~/.config/seihou/
├── config.dhall
├── modules/        # user-authored modules
└── installed/      # modules installed via `seihou install`
```
