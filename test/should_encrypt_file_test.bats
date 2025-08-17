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

@test "returns success to encrypt file since it has changed since last encryption" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  echo "Hello World 2" >"$file"

  run should_encrypt_file "$file" "$file.gpg"
  assert_success
}

@test "returns failure to encrypt file since the contents are the same" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run should_encrypt_file "$file" "$file.gpg"
  assert_failure
}

@test "returns success because file does not exist yet" {
  local file="$NOTES_DIR/test.md"

  run should_encrypt_file "$file"
  assert_success
}
