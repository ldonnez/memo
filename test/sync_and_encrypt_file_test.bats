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

@test "encrypts the file and builds cache when the encrypted gpg file does not exist yet" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run sync_and_encrypt_file "$file" "$file.gpg"
  assert_success
  assert_output --partial "Encrypted: $file.gpg
Cache updated (1 file(s) changed)"

  run file_exists "$file.gpg"
  assert_success
}

@test "reencrypts the file and builds cache when the encrypted gpg file exists and file content changed" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"


  gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  printf "Changed" >"$file"

  run sync_and_encrypt_file "$file" "$file.gpg"
  assert_success
  assert_output --partial "Encrypted: $file.gpg
Cache updated (1 file(s) changed)"

  run file_exists "$file.gpg"
  assert_success
}

@test "Does nothing when encrypted gpg files exists and content is not changed" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run sync_and_encrypt_file "$file" "$file.gpg"
  assert_success
  assert_output ""

  run file_exists "$file.gpg"
  assert_success
}
