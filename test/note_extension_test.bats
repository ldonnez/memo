#!/usr/bin/env bats
# Covers the note extension helpers: notes are written with $EXTENSION
# (asc by default) while both .asc and .gpg are read, so notes written by older
# versions of memo keep working.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "_file_is_gpg accepts both note extensions" {
  run _file_is_gpg "$NOTES_DIR/test.md.asc"
  assert_success

  run _file_is_gpg "$NOTES_DIR/test.md.gpg"
  assert_success

  run _file_is_gpg "$NOTES_DIR/test.md"
  assert_failure

  run _file_is_gpg "$NOTES_DIR/test.asc.md"
  assert_failure
}

@test "_strip_note_extension strips either extension" {
  run _strip_note_extension "$NOTES_DIR/test.md.asc"
  assert_output "$NOTES_DIR/test.md"

  run _strip_note_extension "$NOTES_DIR/test.md.gpg"
  assert_output "$NOTES_DIR/test.md"

  run _strip_note_extension "$NOTES_DIR/test.md"
  assert_output "$NOTES_DIR/test.md"
}

@test "_strip_note_extension strips one trailing extension only" {
  run _strip_note_extension "$NOTES_DIR/test.md.gpg.asc"
  assert_output "$NOTES_DIR/test.md.gpg"

  run _strip_note_extension "$NOTES_DIR/report.gpg.md"
  assert_output "$NOTES_DIR/report.gpg.md"
}

@test "the configured EXTENSION is a supported note extension" {
  local config_file="$BATS_TEST_TMPDIR/config"
  printf 'EXTENSION="pgp"\n' >"$config_file"
  _load_config "$config_file"

  run _file_is_gpg "$NOTES_DIR/test.md.pgp"
  assert_success

  run _file_is_gpg "$NOTES_DIR/test.md.txt"
  assert_failure

  run _strip_note_extension "$NOTES_DIR/test.md.pgp"
  assert_output "$NOTES_DIR/test.md"

  # Written with it, then read back as a note again
  run memo "custom.md"
  assert_success
  run _file_exists "$NOTES_DIR/custom.md.pgp"
  assert_success

  run memo "custom.md"
  assert_success

  run memo_decrypt_files "all"
  assert_success

  run cat "$NOTES_DIR/custom.md"
  assert_output --partial "# custom"
}

@test "memo files lists the configured extension" {
  local rg_args="$BATS_TEST_TMPDIR/rg-args"

  # shellcheck disable=SC2317,SC2329
  rg() {
    printf "%s\n" "$*" >"$rg_args"
  }

  # shellcheck disable=SC2317,SC2329
  fzf() {
    printf "%s\n" "$NOTES_DIR/one.md.asc"
  }

  # shellcheck disable=SC2317,SC2329
  memo() {
    return 0
  }

  local config_file="$BATS_TEST_TMPDIR/config"
  printf 'EXTENSION="pgp"\n' >"$config_file"
  _load_config "$config_file"

  run memo_files
  assert_success

  run cat "$rg_args"
  assert_output --partial "--glob *.asc"
  assert_output --partial "--glob *.gpg"
  assert_output --partial "--glob *.pgp"
}

@test "a supported EXTENSION is not added to the list twice" {
  local config_file="$BATS_TEST_TMPDIR/config"
  printf 'EXTENSION="gpg"\n' >"$config_file"
  _load_config "$config_file"

  assert_equal "${#SUPPORTED_EXTENSIONS[@]}" "2"

  _load_config "$config_file"
  assert_equal "${#SUPPORTED_EXTENSIONS[@]}" "2"
}

@test "an invalid EXTENSION is rejected" {
  local config_file="$BATS_TEST_TMPDIR/config"

  printf 'EXTENSION=".asc"\n' >"$config_file"
  run _load_config "$config_file"
  assert_failure
  assert_output --partial "EXTENSION must be a bare extension"

  printf 'EXTENSION=""\n' >"$config_file"
  run _load_config "$config_file"
  assert_failure

  printf 'EXTENSION="notes/asc"\n' >"$config_file"
  run _load_config "$config_file"
  assert_failure

  # A leading dash would turn the note name into an option for the find and rg
  # calls that match on the extensions.
  printf 'EXTENSION="-asc"\n' >"$config_file"
  run _load_config "$config_file"
  assert_failure

  printf 'EXTENSION="_asc"\n' >"$config_file"
  run _load_config "$config_file"
  assert_success
  # Not via run: the extension is added to the global array, which a subshell
  # would swallow.
  _load_config "$config_file"
  assert_equal "${SUPPORTED_EXTENSIONS[*]}" "asc gpg _asc"
}

@test "_make_tempfile drops either note extension" {
  run _make_tempfile "$NOTES_DIR/test.md.asc"
  assert_output --regexp "/memo\.[^/]+/test\.md"

  run _make_tempfile "$NOTES_DIR/test.md.gpg"
  assert_output --regexp "/memo\.[^/]+/test\.md"
}

@test "memo files lists both note extensions" {
  local rg_args="$BATS_TEST_TMPDIR/rg-args"

  # Mock rg to record its arguments, since the globs are memo_files' only way
  # to tell which notes exist
  # shellcheck disable=SC2329
  rg() {
    printf "%s\n" "$*" >"$rg_args"
  }

  # shellcheck disable=SC2329
  fzf() {
    printf "%s\n" "$NOTES_DIR/one.md.asc"
  }

  # shellcheck disable=SC2329
  memo() {
    return 0
  }

  run memo_files
  assert_success

  run cat "$rg_args"
  assert_output --partial "--glob *.asc"
  assert_output --partial "--glob *.gpg"
}

@test "decrypt-files decrypts both note extensions" {
  _gpg_encrypt "$NOTES_DIR/one.md.asc" <<<"Hello one"
  _gpg_encrypt "$NOTES_DIR/two.md.gpg" <<<"Hello two"
  rm -f "$NOTES_DIR/one.md" "$NOTES_DIR/two.md"

  run memo_decrypt_files "all"
  assert_success

  run cat "$NOTES_DIR/one.md"
  assert_output "Hello one"

  run cat "$NOTES_DIR/two.md"
  assert_output "Hello two"
}

@test "a new note is written with the extension from EXTENSION" {
  EXTENSION="gpg" run memo "from-config.md"
  assert_success

  run _file_exists "$NOTES_DIR/from-config.md.gpg"
  assert_success

  run _file_exists "$NOTES_DIR/from-config.md.asc"
  assert_failure
}

@test "an explicitly given .gpg output file stays .gpg" {
  run memo_encrypt "$NOTES_DIR/explicit.md.gpg" <<<"Hello World"
  assert_success

  run _file_exists "$NOTES_DIR/explicit.md.gpg"
  assert_success

  run _file_exists "$NOTES_DIR/explicit.md.asc"
  assert_failure
}
