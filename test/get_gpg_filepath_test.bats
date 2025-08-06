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

@test "returns filepath with .gpg if file exists with .gpg" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run get_gpg_filepath "$file"
  assert_success
  assert_output "$file.gpg"
}

@test "returns filepath with .gpg if file is .gpg" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run get_gpg_filepath "$file.gpg"
  assert_success
  assert_output "$file.gpg"
}

@test "returns failure when file or file.gpg does not exist" {
  local file="i-do-not-exist"

  run get_gpg_filepath "$file"
  assert_failure
}
