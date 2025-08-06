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

@test "returns filepath with .gpg when file misses .gpg" {
  local file="$NOTES_DIR/test.md"

  run _get_output_gpg_filepath "$file"
  assert_output "$file.gpg"
}

@test "returns filepath with .gpg when file is gpg" {
  local file="$NOTES_DIR/test.md.gpg"

  run _get_output_gpg_filepath "$file.gpg"
  assert_output "$file.gpg"
}
