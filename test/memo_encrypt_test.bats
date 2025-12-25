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

@test "encrypts content from stdin when first argument is '-' and output path is provided" {
  local output_gpg="$NOTES_DIR/stdin_test.md.gpg"
  local secret_msg="This content came from stdin"

  # We pipe the message into the function and pass '-' as the source
  run memo_encrypt "$output_gpg" <<<"$secret_msg"
  assert_success

  run cat "$output_gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "returns 'Extension not supported' when input file uses an extension that is not supported" {
  local file="test.word"

  run memo_encrypt "$file.gpg" "$file"
  assert_failure
  assert_output "Extension: word not supported"
}
