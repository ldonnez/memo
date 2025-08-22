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

@test "encrypts all the files and removes the originals in the notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run memo_encrypt "$file" "$file.gpg"
  assert_success
  assert_output ""

  run cat "$file.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "returns 'Input file does not exist' when input file is not present" {
  local file="i-do-not-exist"

  run memo_encrypt "$file" "$file.gpg"
  assert_failure
  assert_output "File not found: $file"

}
