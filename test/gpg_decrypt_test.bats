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

@test "decrypts file to given output path" {
  local input_path="$NOTES_DIR/test.md"

  _gpg_encrypt "$input_path.gpg" <<<"Hello World"

  run _gpg_decrypt "$input_path.gpg" "$input_path.md"
  assert_success
}
