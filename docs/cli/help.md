# seihou help

Show help for commands and topics.

## Usage

```
seihou help [TOPIC]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `TOPIC` | No | Help topic to display. If omitted, lists available topics. |

## Available Topics

| Topic | Description |
|-------|-------------|
| `modules` | How Seihou modules work |
| `variables` | Variable declaration, resolution, and overrides |
| `contexts` | Using contexts for environment-specific config |
| `config` | Config scopes, reading, and writing values |
| `git-repository` | Sharing and installing modules from git |

## Examples

```sh
# List available topics
seihou help

# Read about variables
seihou help variables
```
