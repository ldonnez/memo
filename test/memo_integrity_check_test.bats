#!/usr/bin/env bats

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

@test "Passes all integrity checks" {
  local file="$NOTES_DIR/test.md.gpg"

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md.gpg"
  _gpg_encrypt "$file2" <<<"Hello World\n"

  run memo_integrity_check
  assert_success
  assert_output --partial "All files passed the integrity check."
}

@test "Does not pass integrity check test.md is not encrypted" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md.gpg"
  printf "Hello World\n" >"$file2"
  _gpg_encrypt "$file2" <<<"Hello World\n"

  run memo_integrity_check
  assert_failure
  assert_output --partial "Some files failed the integrity check. Please investigate."
}

@test "Takes ignored files into account" {
  local ignore="$NOTES_DIR/.ignore"
  printf "ignored.txt\n" >"$ignore"

  local txtfile="$NOTES_DIR/ignored.txt"
  printf "Ignored" >"$txtfile"

  local mdfile="$NOTES_DIR/test.md.gpg"
  _gpg_encrypt "$mdfile" <<<"Hello World"

  run memo_integrity_check
  assert_success
  assert_output --partial "Ignored (.ignore): .ignore
Ignored (.ignore): ignored.txt"
}

@test "Does not check files with unsupported extension" {
  local wordfile="$NOTES_DIR/test.word"
  printf "Hello Word" >"$wordfile"

  local mdfile="$NOTES_DIR/test.md.gpg"
  _gpg_encrypt "$mdfile" <<<"Hello World"

  run memo_integrity_check
  assert_success
  assert_output --partial "Extension: word not supported"
}
