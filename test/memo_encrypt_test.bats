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

@test "encrypts all the files and removes the originals in the notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run memo_encrypt "$file.gpg" "$file"
  assert_success
  assert_output ""

  run cat "$file.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "encrypts content from stdin when first argument is '-' and output path is provided" {
  local output_gpg="$NOTES_DIR/stdin_test.md.gpg"
  local secret_msg="This content came from stdin"

  # We pipe the message into the function and pass '-' as the source
  run memo_encrypt "$output_gpg" <<<"$secret_msg"
  assert_success

  run cat "$output_gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "returns 'Input file does not exist' when input file is not present" {
  local file="i-do-not-exist.md"

  run memo_encrypt "$file.gpg" "$file"
  assert_failure
  assert_output "File not found: $file"

}

@test "returns 'Extension not wupported' when input file uses an extension that is not supported" {
  local file="test.word"

  run memo_encrypt "$file.gpg" "$file"
  assert_failure
  assert_output "Extension: word not supported"
}
