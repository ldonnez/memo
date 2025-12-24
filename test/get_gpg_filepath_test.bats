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

@test "returns filepath with .gpg if file exists with .gpg" {
  local file
  file="$NOTES_DIR/test.md.gpg"

  _gpg_encrypt "$file" <<<"Hello World"

  run _get_gpg_filepath "$file"
  assert_success
  assert_output "$file"
}

@test "returns filepath with .gpg if given file is not .gpg" {
  local file
  file="$NOTES_DIR/test.md"

  _gpg_encrypt "$file.gpg" <<<"Hello World"

  run _get_gpg_filepath "$file"
  assert_success
  assert_output "$file.gpg"
}

@test "returns failure when file or file.gpg does not exist" {
  local file="i-do-not-exist"

  run _get_gpg_filepath "$file"
  assert_failure
}
