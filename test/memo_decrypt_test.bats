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

@test "decrypts file with gpg message to stdout" {
  local file="$NOTES_DIR/file.md.gpg"
  printf "Hello World!" > "$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo_decrypt "$file.gpg"
  assert_success
  assert_output "Hello World!"
}

@test "returns 'File not found' when input file does not exist" {
  local file="i-do-not-exist.gpg"

  run memo_decrypt "$file"
  assert_failure
  assert_output "File not found: $file"
}
