#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
}

@test "returns decrypted file path and contents" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run decrypt_file_to_temp "$file.gpg"
  assert_success
  assert_output "/dev/shm/memo-test.md"

  run cat "/dev/shm/memo-test.md"
  assert_output "Hello World"

  # Cleanup
  rm -f "$file" "$file.gpg" "/dev/shm/memo-test.md"
}

@test "fails on invalid file" {
  local file="$NOTES_DIR/test.gpg"
  printf "not encrypted" >"$file"

  run decrypt_file_to_temp "$file"
  assert_failure

  rm -f "$file"
}
