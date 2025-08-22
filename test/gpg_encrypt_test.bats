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

@test "encrypts file to same path when no output_path (second arg) is given" {
  local input_path="$NOTES_DIR/test.md"
  printf "Hello World" >"$input_path"

  run gpg_encrypt "$input_path" "$input_path.gpg"
  assert_success

  run file_exists "$input_path.gpg"
  assert_success

  run cat "$input_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "encrypts file to given output_path" {
  local input_path="$NOTES_DIR/test.md"
  printf "Hello World" >"$input_path"

  local output_path="$NOTES_DIR/test.md"

  run gpg_encrypt "$input_path" "$output_path.gpg"
  assert_success

  run file_exists "$output_path.gpg"
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
  export KEY_IDS="mock@example.com,test2@example.com"

  local input_path="$NOTES_DIR/test_multi.md"
  printf "Hello Multiple" >"$input_path"

  run gpg_encrypt "$input_path" "$input_path.gpg"
  assert_success

  run file_exists "$input_path.gpg"
  assert_success

  run cat "$input_path.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "does not leave unencrypted file when encryption fails" {
  # shellcheck disable=SC2030,SC2031
  export KEY_IDS="missing@example.com"

  local input_path="$NOTES_DIR/test_secure.md"
  printf "Sensitive" >"$input_path"

  run gpg_encrypt "$input_path" "$input_path.gpg"
  assert_failure

  run file_exists "$input_path.gpg"
  assert_failure
}
