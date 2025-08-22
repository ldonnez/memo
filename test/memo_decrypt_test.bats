#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  load test_helper.bash
  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
}

@test "decrypts file with gpg message to stdout" {
  local plaintext="Hello World!"
  local file_path="$NOTES_DIR/file.md.gpg"

  make_encrypted_file "$plaintext" "$file_path"

  run memo_decrypt "$file_path"
  assert_success
  assert_output "Hello World!"
}

@test "returns 'File not found' when input file does not exist" {
  local file_path="i-do-not-exist.gpg"

  run memo_decrypt "$file_path"
  assert_failure
  assert_output "File not found: $file_path"
}
