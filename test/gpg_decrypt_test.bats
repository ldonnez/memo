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

@test "decrypts file to given output path" {
  local input_path="$NOTES_DIR/test.md"

  _gpg_encrypt "$input_path.gpg" <<<"Hello World"

  run _gpg_decrypt "$input_path.gpg" "$input_path.md"
  assert_success
}

@test "decrypts a passphrase note with a passphrase file" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local input_path="$NOTES_DIR/test_sym.md"
    _gpg_encrypt "$input_path.gpg" "" "true" <<<"Hello Symmetric"

    run _gpg_decrypt "$input_path.gpg" "$input_path.md"
    assert_success

    run cat "$input_path.md"
    assert_output "Hello Symmetric"
  )
}

@test "fails to decrypt a passphrase note with the wrong passphrase" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local input_path="$NOTES_DIR/test_sym.md"
    _gpg_encrypt "$input_path.gpg" "" "true" <<<"Hello Symmetric"

    printf "wrong passphrase" >"$MEMO_PASSPHRASE_FILE"

    run _gpg_decrypt "$input_path.gpg"
    assert_failure
  )
}
