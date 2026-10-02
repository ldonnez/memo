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

@test "add the note extension to output file when missing" {
  local output_path="$NOTES_DIR/test.md"

  run _gpg_encrypt "$output_path" <<<"Hello World from stdin"
  assert_success

  run _file_exists "$output_path.asc"
  assert_success

  run cat "$output_path.asc"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"

  run _gpg_decrypt "$output_path.asc"
  assert_output --partial "Hello World from stdin"
}

@test "adds the .gpg extension when EXTENSION is gpg" {
  local output_path="$NOTES_DIR/test.md"

  EXTENSION="gpg" run _gpg_encrypt "$output_path" <<<"Hello World from stdin"
  assert_success

  run _file_exists "$output_path.gpg"
  assert_success

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
  # run in subshell to avoid collision with other tests.
  (
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
    local GPG_RECIPIENTS="mock@example.com,test2@example.com"

    local output_path="$NOTES_DIR/test_multi.md"
    printf "Hello Multiple" >"$output_path"

    run _gpg_encrypt "$output_path.gpg" "$output_path"
    assert_success

    run _file_exists "$output_path.gpg"
    assert_success

    run cat "$output_path.gpg"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"
  )
}

@test "does not leave unencrypted file when encryption fails" {
  # run in subshell to avoid collision with other tests.
  (
    # shellcheck disable=SC2030,SC2031
    export GPG_RECIPIENTS="missing@example.com"

    local output_path="$NOTES_DIR/test_secure.md"
    printf "Sensitive" >"$output_path"

    run _gpg_encrypt "$output_path.gpg" "$output_path"
    assert_failure

    run _file_exists "$output_path.gpg"
    assert_failure
  )
}

@test "encrypts file with only found recipients" {
  # run in subshell to avoid collision with other tests.
  (
    # shellcheck disable=SC2030,SC2031
    local GPG_RECIPIENTS="i-do-not-exist@example.com,mock@example.com"

    local output_path="$NOTES_DIR/test_multi.md"
    printf "Hello Multiple" >"$output_path"

    run _gpg_encrypt "$output_path.gpg" "$output_path"
    assert_output "GPG recipient(s) not found: i-do-not-exist@example.com"
    assert_success

    run _file_exists "$output_path.gpg"
    assert_success

    run cat "$output_path.gpg"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"
  )
}

@test "encrypts symmetrically with a passphrase file" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local output_path="$NOTES_DIR/test_sym.md"

    run _gpg_encrypt "$output_path.gpg" "" "true" <<<"Hello Symmetric"
    assert_success

    run cat "$output_path.gpg"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"

    run _file_is_symmetric "$output_path.gpg"
    assert_success

    run _gpg_decrypt "$output_path.gpg"
    assert_output --partial "Hello Symmetric"
  )
}

@test "encrypts symmetrically without recipients configured" {
  (
    # shellcheck disable=SC2030,SC2031
    local GPG_RECIPIENTS="i-do-not-exist@example.com"
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local output_path="$NOTES_DIR/test_no_recipients.md"
    printf "Hello Symmetric" >"$output_path"

    run _gpg_encrypt "$output_path.gpg" "$output_path" "true"
    assert_success

    run _file_is_symmetric "$output_path.gpg"
    assert_success
  )
}

@test "encrypts symmetrically from a given input file" {
  (
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local output_path="$NOTES_DIR/test_sym_input.md"
    printf "Content from a file" >"$output_path"

    run _gpg_encrypt "$output_path.gpg" "$output_path" "true"
    assert_success

    run _gpg_decrypt "$output_path.gpg"
    assert_output "Content from a file"
  )
}

@test "fails symmetric encryption when the passphrase file is missing" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$NOTES_DIR/nope.txt"

    local output_path="$NOTES_DIR/test_missing_pass.md"

    run _gpg_encrypt "$output_path.gpg" "" "true" <<<"Hello"
    assert_failure
    assert_output --partial "Passphrase file not found: $NOTES_DIR/nope.txt"

    run _file_exists "$output_path.gpg"
    assert_failure
  )
}

@test "keeps encrypting with a recipient key when symmetric is false" {
  local output_path="$NOTES_DIR/test_key.md"

  run _gpg_encrypt "$output_path.gpg" "" "false" <<<"Hello World"
  assert_success

  run _file_is_symmetric "$output_path.gpg"
  assert_failure
}

@test "detects a passphrase note and does not detect a key note" {
  (
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local sym="$NOTES_DIR/sym.md.gpg"
    local key="$NOTES_DIR/key.md.gpg"
    _gpg_encrypt "$sym" "" "true" <<<"sym"
    _gpg_encrypt "$key" <<<"key"

    run _file_is_symmetric "$sym"
    assert_success

    run _file_is_symmetric "$key"
    assert_failure

    run _file_is_symmetric "$NOTES_DIR/does_not_exist.gpg"
    assert_failure
  )
}

@test "encrypts symmetrically with a passphrase from the environment" {
  (
    # shellcheck disable=SC2030,SC2031
    export MEMO_TEST_PASSPHRASE="secret passphrase"
    local MEMO_PASSPHRASE_ENV="MEMO_TEST_PASSPHRASE"

    local output_path="$NOTES_DIR/test_env.md"

    run _gpg_encrypt "$output_path.gpg" "" "true" <<<"Hello Symmetric"
    assert_success

    run _file_is_symmetric "$output_path.gpg"
    assert_success

    run _gpg_decrypt "$output_path.gpg"
    assert_output --partial "Hello Symmetric"
  )
}

@test "fails when the passphrase environment variable is not set" {
  (
    # shellcheck disable=SC2030,SC2031
    unset MEMO_TEST_PASSPHRASE
    local MEMO_PASSPHRASE_ENV="MEMO_TEST_PASSPHRASE"

    local output_path="$NOTES_DIR/test_env_missing.md"

    run _gpg_encrypt "$output_path.gpg" "" "true" <<<"Hello"
    assert_failure
    assert_output --partial "Passphrase environment variable not set: MEMO_TEST_PASSPHRASE"

    run _file_exists "$output_path.gpg"
    assert_failure
  )
}

@test "a passphrase file wins over the environment" {
  (
    # shellcheck disable=SC2030,SC2031
    export MEMO_TEST_PASSPHRASE="from the environment"
    local MEMO_PASSPHRASE_ENV="MEMO_TEST_PASSPHRASE"
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "from a file" >"$MEMO_PASSPHRASE_FILE"

    local output_path="$NOTES_DIR/test_precedence.md"
    run _gpg_encrypt "$output_path.gpg" "" "true" <<<"Hello"
    assert_success

    # The file is preferred, so dropping the environment one changes nothing.
    unset MEMO_PASSPHRASE_ENV
    run _gpg_decrypt "$output_path.gpg"
    assert_output --partial "Hello"

    # Only the environment passphrase is left, and it is the wrong one.
    unset MEMO_PASSPHRASE_FILE
    export MEMO_PASSPHRASE_ENV="MEMO_TEST_PASSPHRASE"
    run _gpg_decrypt "$output_path.gpg"
    assert_failure
  )
}
