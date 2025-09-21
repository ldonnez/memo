# memo

**memo** is a secure, CLI-based note-taking system with transparent [GPG](https://gnupg.org/) encryption.
It lets you create, edit, search, and manage your notes as easily as plain text.

---

<a href="https://github.com/ldonnez/memo/actions"><img src="https://github.com/ldonnez/memo/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status"></a>
<a href="http://github.com/ldonnez/memo/releases"><img src="https://img.shields.io/github/v/tag/ldonnez/memo" alt="Version"></a>
<a href="https://github.com/ldonnez/memo?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/ldonnez/memo" alt="License"></a>

# Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Install with a single command](#install-with-a-single-command)
  - [Install with Git](#install-with-git)
- [Configuration](#configuration)
  - [Example config](#example-config)
- [Usage](#usage)
  - [Default Behavior](#default-behavior)
  - [Commands](#commands)
  - [Examples](#examples)
- [Development Guide](#development-guide)
  - [Prerequisites](#prerequisites)
  - [File Structure](#file-structure)
  - [Dev Install](#dev-install)
  - [Clean](#clean)
  - [Uninstall](#uninstall)
  - [Build docker image](#build-docker-image)
  - [Run Dev Shell](#run-dev-shell)
  - [Run tests](#run-tests)
- [Roadmap](#roadmap)
- [License](#License)

# Features

- **Always encrypted** — only `.gpg` files are stored on disk
- **Transparent editing** — decrypt to a temp file (or inline in $EDITOR), auto-encrypt on save
- **Fast search** — search with `ripgrep` + `fzf` by using the cache.
- **Safe deletion** — delete notes interactively (or with `--force`), cache updates automatically
- **Ignore rules** — `.ignore` file with defaults (`.git/*`, `.DS_Store`, etc.)
- **Cross-platform** — Linux & macOS

# Requirements

- GPG
- gpg-agent
- fzf
- ripgrep
- Neovim (optional) $EDITOR is used as default editor for opening notes.

# Installation

## Install with a single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ldonnez/memo/main/install.sh)
```

## Install with Git:

Clone the repo and run the install script:

```bash
git clone https://github.com/ldonnez/memo.git
bash install.sh
```

This will:

- Download the latest release from Github.
- Install the Go binary cache_builder into `$HOME/.local/libexec/memo`
- Install the memo script into `$HOME/.local/bin`

**Ensure ~/.local/bin is in your $PATH**!

# Configuration

Memo is designed to work with sensible defaults, but you can customize its behavior by creating a config file.

Memo adheres to the XDG Base Directory Specification. Your configuration file should be located at: `$XDG_CONFIG_HOME/memo/config` (usually `$HOME/memo/config`).
You can override any of the default settings by adding them to this file.

## Example config

Here is an example of the configuration file with all the default settings. You can copy this into your config file and modify the values as needed.

```bash
# A comma-separated list of public key IDs (e.g., emails or GPG IDs) used for encryption.
# If left empty, GPG's --default-recipient-self option is used.
KEY_IDS=

# The directory where all your notes are stored.
NOTES_DIR=$HOME/notes

# The default text editor for opening notes. If this variable is empty, memo will use the $EDITOR environment variable.
EDITOR_CMD=$EDITOR

# The directory where memo stores its cache file (notes.cache).
CACHE_DIR=$HOME/.cache/memo

# A comma-separated list of file extensions that memo supports.
# This list is used for operations like batch encryption.
SUPPORTED_EXTENSIONS="md,org,txt"

# The default file extension for new notes created with memo.
DEFAULT_EXTENSION="md"

# The default file to open when running memo without any arguments.
DEFAULT_FILE="inbox.md"

# A comma-separated list of files or patterns to ignore during various operations.
DEFAULT_IGNORE=".ignore,.git/*,.DS_store"
```

# Usage

```bash
memo [FILE] [LINE]
memo [COMMAND] [ARGS...]
```

## Default behavior

Opening and editing files is the default action:

`memo` → Opens the default file (creates it if missing).

`memo` FILE → Opens or creates a file named FILE.

## Commands

| Command                          | Description                                                                                                                               |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `--encrypt INPUTFILE OUTPUTFILE` | Encrypt `INPUTFILE` into `OUTPUTFILE.gpg`.                                                                                                |
| `--decrypt FILE.gpg`             | Decrypt `FILE.gpg` and print plaintext to stdout.                                                                                         |
| `--encrypt-files [FILES...]`     | Encrypt files in-place inside the notes directory. Accepts `all`, explicit file names, or glob patterns (e.g. `dir/*`).                   |
| `--decrypt-files [FILES...]`     | Decrypt `.gpg` files in-place inside the notes directory. Accepts `all`, explicit `.gpg` file names, or glob patterns (e.g. `dir/*.gpg`). |
| `--delete [FILES...]`            | Delete one or more files and update cache.                                                                                                |
| `--files`                        | Browse all files in `fzf` (decrypts preview automatically).                                                                               |
| `--grep <query>`                 | Search through files using cached index.                                                                                                  |
| `--cache [FILES...]`             | Incrementally build the memo cache for faster searching with ripgrep.                                                                     |
| `--integrity-check`              | Verify the integrity of all files in the notes directory (skips files ignored by `.ignore`).                                              |
| `--upgrade`                      | Upgrade `memo` in-place.                                                                                                                  |
| `--uninstall`                    | Uninstall `memo`.                                                                                                                         |
| `--version`                      | Print current version.                                                                                                                    |
| `--help`                         | Show help message.                                                                                                                        |

## Examples

```bash

# Open default file
memo

# Open or create "todo.md" inside notes dir
memo todo.md

# Encrypt and decrypt notes
memo --encrypt notes.txt out.gpg
memo --decrypt out.gpg

# Encrypt/decrypt multiple files
memo --encrypt-files all
memo --decrypt-files *.gpg

# Search notes for "projectX"
memo --grep projectX
```

# Development Guide

Explains how to work with the **Makefile** and development workflow for memo.

## Prerequisites

Make sure the following are installed before building or testing:

- [Go](https://go.dev/)
- [Bats](https://github.com/bats-core/bats-core) (optional if you use Docker)
- [Docker](https://www.docker.com/)

## File Structure

memo.sh → Main Bash wrapper script.

cmd/cache_builder/ → Go program for building the memo search cache.

bin/cache_builder → Compiled binary (ignored in Git).

test/ → Bats test files.

## Dev Install

Useful for rapid development (no need to reinstall after changes). (Ensure ~/.local/bin is in your $PATH.)

- Builds cache builder in bin/cache_builder
- Symlinks bin/cache_builder → ~/.local/libexec/memo/cache_builder.
- Symlinks memo.sh → ~/.local/bin/memo.

```bash
make dev
```

## Clean

Removes build artifacts (bin/cache_builder).

```bash
make clean
```

## Uninstall

Deletes the installed binary and script:

- ~/.local/libexec/memo/
- ~/.local/bin/memo

```bash
make uninstall
```

## Build docker image

The project supports Docker for isolated builds and tests.

```bash
make docker/build-image
```

## Run Dev Shell

Drops into a Bash shell inside the container.

Mounts the current project directory into /opt.

Handy for running isolated bats tests manually.

```bash
make docker/shell
```

## Run tests

Runs Go tests inside Docker: go test -v ./....

Runs Bats tests inside Docker.

```bash
make test
```

# Roadmap

- [ ] Neovim Integration

# [License](LICENSE)

MIT License

Copyright (c) 2025 Lenny Donnez
