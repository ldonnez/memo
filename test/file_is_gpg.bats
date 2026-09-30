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

@test "returns success when is gpg" {
  local file="$NOTES_DIR/test.md.gpg"
  touch "$file"

  run _file_is_gpg "$file"
  assert_success
}

@test "returns failure when file is not gpg" {
  run _file_is_gpg "$NOTES_DIR/not-gpg.md"
  assert_failure
}

@test "recognises a passphrase note as a gpg message" {
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local file="$NOTES_DIR/sym.md.gpg"
    _gpg_encrypt "$file" "" "true" <<<"Hello Symmetric"

    run _file_is_gpg_message "$file"
    assert_success
  )
}

@test "does not recognise a plaintext file as a gpg message" {
  printf "plain" >"$NOTES_DIR/plain.md"

  run _file_is_gpg_message "$NOTES_DIR/plain.md"
  assert_failure
}

@test "recognises a passphrase note without a passphrase available" {
  local pass_file="$TEST_HOME/pass.txt"
  printf "secret passphrase" >"$pass_file"

  local file="$NOTES_DIR/sym_no_prompt.md.gpg"
  MEMO_PASSPHRASE_FILE="$pass_file" _gpg_encrypt "$file" "" "true" <<<"Hello Symmetric"

  # Nothing in memo.sh may ask for the passphrase to look at a note. The
  # gpg-agent from setup_suite answers every prompt with a failure, so a
  # prompting call would end up as a failing assertion here.
  run _file_is_symmetric "$file"
  assert_success
  refute_output --partial "pinentry"

  run _file_is_gpg_message "$file"
  assert_success
}
