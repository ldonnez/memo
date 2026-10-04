#!/usr/bin/env bats
# Tests for the standalone tab-completion scripts (completions/_memo for zsh,
# completions/memo.bash for bash). These are pty-free and deterministic so they
# run cleanly under `make test` in the docker CI container.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Isolated config + notes dir so _memo_get_notes_dir resolves deterministically
  # instead of reading the developer's real $HOME/notes.
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/memo"
  printf 'NOTES_DIR="%s"\n' "$BATS_TEST_TMPDIR/notes" >"$XDG_CONFIG_HOME/memo/config"
  export NOTES_DIR="$BATS_TEST_TMPDIR/notes"
  mkdir -p "$NOTES_DIR"
}

@test "bash: memo is wired to the _memo completer" {
  run bash -c '
    source "completions/memo.bash"
    complete -p memo
  '
  assert_success
  assert_output --partial "-F _memo memo"
}

@test "bash: completes subcommands" {
  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo dec)
    COMP_CWORD=1
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "decrypt"
  assert_output --partial "decrypt-files"
  refute_output --partial "encrypt"
}

@test "bash: decrypt-files suggests all plus only note files" {
  touch "$NOTES_DIR/alpha.txt"
  touch "$NOTES_DIR/secret.gpg"
  touch "$NOTES_DIR/deep.asc"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo decrypt-files "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "all"
  assert_output --partial "secret.gpg"
  assert_output --partial "deep.asc"
  refute_output --partial "alpha.txt"
}

@test "bash: decrypt does not suggest all" {
  touch "$NOTES_DIR/alpha.txt"
  touch "$NOTES_DIR/secret.gpg"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo decrypt "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "secret.gpg"
  refute_output --partial "all"
  refute_output --partial "alpha.txt"
}

@test "bash: encrypt-files suggests all, options, and no note files" {
  touch "$NOTES_DIR/alpha.txt"
  touch "$NOTES_DIR/secret.gpg"
  touch "$NOTES_DIR/deep.asc"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo encrypt-files "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "all"
  assert_output --partial "--dry-run"
  assert_output --partial "--exclude"
  assert_output --partial "alpha.txt"
  refute_output --partial "secret.gpg"
  refute_output --partial "deep.asc"
}

@test "bash: encrypt-files filters options and files by prefix" {
  touch "$NOTES_DIR/alpha.txt"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo encrypt-files --ex)
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "--exclude"
  refute_output --partial "--dry-run"
  refute_output --partial "alpha.txt"
}

@test "bash: upgrade completes -f and --force" {
  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo upgrade "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "-f"
  assert_output --partial "--force"
}

@test "bash: _memo_get_notes_dir honors NOTES_DIR from config" {
  run bash -c '
    source "completions/memo.bash"
    _memo_get_notes_dir
  '
  assert_success
  assert_output "$NOTES_DIR"
}

@test "bash: decrypt-files completes notes with the configured extension" {
  printf 'NOTES_DIR="%s"\nEXTENSION="pgp"\n' "$NOTES_DIR" >"$XDG_CONFIG_HOME/memo/config"
  touch "$NOTES_DIR/secret.pgp"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo decrypt-files "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "secret.pgp"
}

@test "bash: encrypt-files does not suggest notes with the configured extension" {
  printf 'NOTES_DIR="%s"\nEXTENSION="pgp"\n' "$NOTES_DIR" >"$XDG_CONFIG_HOME/memo/config"
  touch "$NOTES_DIR/alpha.txt"
  touch "$NOTES_DIR/secret.pgp"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo encrypt-files "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "alpha.txt"
  refute_output --partial "secret.pgp"
}

@test "bash: _memo_get_extensions lists the built-ins plus the configured one" {
  run bash -c '
    source "completions/memo.bash"
    _memo_get_extensions
  '
  assert_success
  assert_output "asc gpg"

  printf 'NOTES_DIR="%s"\nEXTENSION="pgp"\n' "$NOTES_DIR" >"$XDG_CONFIG_HOME/memo/config"

  run bash -c '
    source "completions/memo.bash"
    _memo_get_extensions
  '
  assert_success
  assert_output "asc gpg pgp"

  # Already a built-in, so it is not listed twice
  printf 'NOTES_DIR="%s"\nEXTENSION="gpg"\n' "$NOTES_DIR" >"$XDG_CONFIG_HOME/memo/config"

  run bash -c '
    source "completions/memo.bash"
    _memo_get_extensions
  '
  assert_success
  assert_output "asc gpg"
}

@test "bash: sync/init offer git only once, not after it is present" {
  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo sync "")
    COMP_CWORD=2
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  assert_output --partial "git"

  run bash -c '
    source "completions/memo.bash"
    COMP_WORDS=(memo sync git "")
    COMP_CWORD=3
    _memo
    printf "%s\n" "${COMPREPLY[@]}"
  '
  assert_success
  refute_output --partial "git"
}

@test "zsh: sync/init offer git only on the first argument slot" {
  run cat "completions/_memo"
  assert_output --partial "(( CURRENT == 3 )) && _values 'argument' git"
}

@test "zsh: completion file is syntactically valid" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -n "completions/_memo"
  assert_success
  assert_output ""
}

@test "zsh: completion file declares #compdef memo" {
  run head -n 1 "completions/_memo"
  assert_output "#compdef memo"
}

@test "zsh: commands are offered with _describe" {
  run cat "completions/_memo"
  assert_output --partial "_describe 'command' commands"
  assert_output --partial "decrypt-files:Decrypt .asc and .gpg notes in-place"
}

@test "zsh: decrypt-files completes note files under NOTES_DIR" {
  run cat "completions/_memo"
  assert_output --partial "_files -W"
  assert_output --partial "-g '*.asc'"
  assert_output --partial "-g '*.gpg'"
}

@test "zsh: encrypt-files excludes note files" {
  run cat "completions/_memo"
  assert_output --partial "-g '^*.asc'"
  assert_output --partial "-g '^*.gpg'"
}

@test "zsh: completes the extension set with EXTENSION as well" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c '
    export XDG_CONFIG_HOME="$1"
    printf "NOTES_DIR=\"$2\"\nEXTENSION=\"pgp\"\n" >"$XDG_CONFIG_HOME/memo/config"

    # Stub the completion widgets, so the arguments they get can be read back
    _files() { print -r -- "files: $*" }
    _values() { : }
    _describe() { : }

    source "completions/_memo" 2>/dev/null
    _memo_args decrypt
    _memo_args encrypt-files
  ' _ "$XDG_CONFIG_HOME" "$NOTES_DIR"
  assert_success
  assert_output --partial "files: -W $NOTES_DIR -g *.asc -g *.gpg -g *.pgp"
  assert_output --partial "files: -W $NOTES_DIR -g ^*.asc -g ^*.gpg -g ^*.pgp"
}

@test "zsh: adds no extra globs without a configured extension" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c '
    export XDG_CONFIG_HOME="$1"

    _files() { print -r -- "files: $*" }
    _values() { : }
    _describe() { : }

    source "completions/_memo" 2>/dev/null
    _memo_args decrypt
  ' _ "$BATS_TEST_TMPDIR/no-config"
  assert_success
  assert_output --partial "files: -W $HOME/notes -g *.asc -g *.gpg"
  refute_output --partial "pgp"
}

@test "zsh: decrypt-files completes all" {
  run cat "completions/_memo"
  assert_output --partial "_values 'argument' all"
  assert_output --partial "-g '*.asc'"
  assert_output --partial "-g '*.gpg'"
}

@test "zsh: encrypt-files completes all and options" {
  run cat "completions/_memo"
  assert_output --partial "_values 'argument' all"
  assert_output --partial "--dry-run[Simulate encryption without making changes]"
  assert_output --partial "--exclude[Exclude a file pattern]"
}

@test "zsh: upgrade completes options with _values" {
  run cat "completions/_memo"
  assert_output --partial "_values 'option'"
  assert_output --partial "-f[Force upgrade]"
  assert_output --partial "--force[Force upgrade]"
}

@test "zsh: help completion lists uninstall" {
  run cat "completions/_memo"
  assert_output --partial "help encrypt decrypt encrypt-files decrypt-files files integrity-check sync init upgrade uninstall"
}

@test "every built-in note extension is completed by both completions" {
  # The built-in list is written out in three places (memo.sh and both
  # completions). Nothing else keeps them in sync, so a new extension added to
  # SUPPORTED_EXTENSIONS has to show up in the completions too.
  run bash -c '
    source "memo.sh"
    printf "%s\n" "${SUPPORTED_EXTENSIONS[@]}"
  '
  assert_success

  local -a builtins=()
  local ext
  while IFS= read -r ext; do
    builtins+=("$ext")
  done < <(printf "%s\n" "$output")

  # The config of this suite sets EXTENSION=asc, so the array still holds just
  # the built-ins here.
  run bash -c '
    source "completions/memo.bash"
    _memo_get_extensions
  '
  assert_success
  assert_output "${builtins[*]}"

  run cat "completions/_memo"
  assert_success
  local zsh_completion="$output"
  for ext in "${builtins[@]}"; do
    assert_regex "$zsh_completion" "-g '\\*\\.$ext'"
    assert_regex "$zsh_completion" "-g '\\^\\*\\.$ext'"
    # zsh skips the extra glob for a built-in, so it has to know all of them
    assert_regex "$zsh_completion" "!= \"$ext\""
  done
}
