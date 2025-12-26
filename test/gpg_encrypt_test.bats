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

@test "encrypts file to same path when input comes from stdin" {
  local output_path="$NOTES_DIR/test.md"

  run _gpg_encrypt "$output_path.gpg" <<<"Hello World from stdin"
  assert_success

  run _file_exists "$output_path.gpg"
  assert_success

  run cat "$output_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"

  run _gpg_decrypt "$output_path.gpg"
  assert_output --partial "Hello World from stdin"
}

@test "add .gpg extension to output file when missing" {
  local output_path="$NOTES_DIR/test.md"

  run _gpg_encrypt "$output_path" <<<"Hello World from stdin"
  assert_success

  run _file_exists "$output_path.gpg"
  assert_success

  run cat "$output_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"

  run _gpg_decrypt "$output_path.gpg"
  assert_output --partial "Hello World from stdin"
}

@test "encrypts file to given output_path" {
  local output_path="$NOTES_DIR/test.md"
  printf "Hello World" >"$output_path"

  local output_path="$NOTES_DIR/test.md"

  run _gpg_encrypt "$output_path.gpg" "$output_path"
  assert_success

  run _file_exists "$output_path.gpg"
  assert_success

  run cat "$output_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "encrypts file with multiple recipients" {
  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 1024
Name-Real: mock user2
Name-Email: test2@example.com
Expire-Date: 0
%commit
EOF
  # shellcheck disable=SC2030,SC2031
  export GPG_RECIPIENTS="mock@example.com,test2@example.com"

  local output_path="$NOTES_DIR/test_multi.md"
  printf "Hello Multiple" >"$output_path"

  run _gpg_encrypt "$output_path.gpg" "$output_path"
  assert_success

  run _file_exists "$output_path.gpg"
  assert_success

  run cat "$output_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "does not leave unencrypted file when encryption fails" {
  # shellcheck disable=SC2030,SC2031
  export GPG_RECIPIENTS="missing@example.com"

  local output_path="$NOTES_DIR/test_secure.md"
  printf "Sensitive" >"$output_path"

  run _gpg_encrypt "$output_path.gpg" "$output_path"
  assert_failure

  run _file_exists "$output_path.gpg"
  assert_failure
}
