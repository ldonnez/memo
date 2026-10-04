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

@test "encrypts content from stdin with a passphrase when --symmetric is given" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local output_gpg="$NOTES_DIR/sym.md.gpg"

    run memo_encrypt --symmetric --passphrase-file "$MEMO_PASSPHRASE_FILE" "$output_gpg" <<<"Secret content"
    assert_success

    run cat "$output_gpg"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"

    run _file_is_symmetric "$output_gpg"
    assert_success

    run memo_decrypt --passphrase-file "$MEMO_PASSPHRASE_FILE" "$output_gpg"
    assert_output --partial "Secret content"
  )
}

@test "prints usage when --symmetric is given without an output file" {
  (
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    run memo_encrypt --symmetric --passphrase-file "$MEMO_PASSPHRASE_FILE"
    assert_failure
    assert_output --partial "Usage: memo encrypt"
  )
}

@test "prints usage when memo_decrypt is given no input file" {
  run memo_decrypt
  assert_failure
  assert_output --partial "Usage: memo decrypt"
}

@test "encrypts content from stdin with a passphrase from the environment" {
  (
    # shellcheck disable=SC2030,SC2031
    export MEMO_TEST_PASSPHRASE="secret passphrase"

    local output_gpg="$NOTES_DIR/env.md.gpg"

    run memo_encrypt --symmetric --passphrase-env MEMO_TEST_PASSPHRASE "$output_gpg" <<<"Secret content"
    assert_success

    run _file_is_symmetric "$output_gpg"
    assert_success

    run memo_decrypt --passphrase-env MEMO_TEST_PASSPHRASE "$output_gpg"
    assert_output --partial "Secret content"
  )
}

@test "prints usage when memo_encrypt is given more than one output file" {
  run memo_encrypt "$NOTES_DIR/first.asc" "$NOTES_DIR/second.md" <<<"Hello"
  assert_failure
  assert_output --partial "Usage: memo encrypt"

  # The first one is not written either
  run _file_exists "$NOTES_DIR/first.asc"
  assert_failure
  run _file_exists "$NOTES_DIR/second.md.asc"
  assert_failure
}

@test "prints usage when memo_decrypt is given more than one file" {
  _gpg_encrypt "$NOTES_DIR/one.md.asc" <<<"Hello one"

  run memo_decrypt "$NOTES_DIR/one.md.asc" "$NOTES_DIR/two.md.asc"
  assert_failure
  assert_output --partial "Usage: memo decrypt"
}
