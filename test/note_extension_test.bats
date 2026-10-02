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
