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

@test "returns success when is gpg" {
  local file="$NOTES_DIR/test.md.gpg"
  touch "$file"

  run _file_is_gpg "$file"
  assert_success
}

@test "returns failure when file is not gpg" {
  run _file_is_gpg "$NOTES_DIR/not-gpg.md"
  assert_failure
}
