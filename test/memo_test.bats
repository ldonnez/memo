#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Ensure clean state
  if [[ "$(uname)" == "Linux" ]]; then
    rm -rf /dev/shm/memo.*
  else
    rm -rf /tmp/memo.*
  fi

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "successfully creates a new memo with $CAPTURE_FILE as filename when it does not exist" {

  local to_be_created_file
  to_be_created_file="$NOTES_DIR/$CAPTURE_FILE.asc"

  run memo
  assert_success
  assert_output ""

  run _file_exists "$to_be_created_file"
  assert_success

  run cat "$to_be_created_file"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"

  if [[ "$(uname)" == "Linux" ]]; then
    run ls /dev/shm/memo.*
    assert_output "ls: cannot access '/dev/shm/memo.*': No such file or directory"
  else
    run ls /tmp/memo.*
    assert_output "ls: /tmp/memo.*: No such file or directory"
  fi
}

@test "successfully creates a new memo with $CAPTURE_FILE.asc as filename when it does not exist" {
  (
    local CAPTURE_FILE="$CAPTURE_FILE.asc"
    local to_be_created_file
    to_be_created_file="$NOTES_DIR/$CAPTURE_FILE"

    run memo
    assert_success
    assert_output ""

    run _file_exists "$to_be_created_file"
    assert_success

    run cat "$to_be_created_file"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"
  )
}

@test "opens a legacy .gpg note and saves it back as .gpg" {
  (
    local file="$NOTES_DIR/legacy.md.gpg"

    _gpg_encrypt "$file" <<<"Hello World"

    # shellcheck disable=SC2329
    fake_editor() {
      printf "Added line" >>"$1"
    }

    local EDITOR_CMD=fake_editor

    # Must specify the .gpg extension to open the .gpg note
    run memo "legacy.md.gpg"
    assert_success
    assert_output ""

    run _file_exists "$NOTES_DIR/legacy.md.asc"
    assert_failure

    run _file_exists "$file"
    assert_success

    run _gpg_decrypt "$file"
    assert_output "Hello World
Added line"
  )
}

@test "successfully edits existing file and do not trigger encryption" {
  local file
  file="$NOTES_DIR/test.md.asc"

  _gpg_encrypt "$file" <<<"Hello World"

  run memo "$file"
  assert_success
  assert_output "No changes detected; skipping re-encryption."
}

@test "edits existing file and triggers encryption" {
  # Run in subshell to avoid collision with other tests
  (
    local file="$NOTES_DIR/test.md.asc"

    _gpg_encrypt "$file" <<<"Hello World"

    # shellcheck disable=SC2329
    fake_editor() {
      printf "Added line" >>"$1"
    }

    # Override editor to append a line automatically
    local EDITOR_CMD=fake_editor

    run memo "$file"

    assert_success
    assert_output ""

    run _gpg_decrypt "$file"
    assert_output "Hello World
Added line"
  )
}

@test "successfully creates new file in notes dir ($NOTES_DIR)" {
  local file="new-file-test.md"

  run memo "$file"
  assert_success
  assert_output ""

  run cat "$NOTES_DIR/$file.asc"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "fails editting existing file since its not in the notes dir ($NOTES_DIR)" {
  local file
  file="test.md.gpg"

  _gpg_encrypt "$file" <<<"Hello World"

  run memo "$file"
  assert_failure
  assert_output "Error: File is not a valid gpg memo in the notes directory."

  # Cleanup
  rm -f "$file"
}

@test "successfully creates new file with any extension in notes dir ($NOTES_DIR)" {
  local file="new-file-test.word"

  run memo "$file"
  assert_success
  assert_output ""

  run cat "$NOTES_DIR/$file.asc"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "keeps a passphrase note passphrase encrypted when it is edited" {
  # Run in subshell to avoid collision with other tests
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local file="$NOTES_DIR/sym_edit.md.gpg"

    _gpg_encrypt "$file" "" "true" <<<"Hello World"

    # shellcheck disable=SC2329
    fake_editor() {
      printf "Added line" >>"$1"
    }

    # Override editor to append a line automatically
    local EDITOR_CMD=fake_editor

    run memo "$file"
    assert_success
    assert_output ""

    # The note must still be a passphrase note, not a recipient-key note.
    run _file_is_symmetric "$file"
    assert_success

    run _gpg_decrypt "$file"
    assert_output "Hello World
Added line"
  )
}

@test "does not re-encrypt a passphrase note that was not changed" {
  # Run in subshell to avoid collision with other tests
  (
    # shellcheck disable=SC2030,SC2031
    local MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"
    printf "secret passphrase" >"$MEMO_PASSPHRASE_FILE"

    local file="$NOTES_DIR/sym_untouched.md.gpg"

    _gpg_encrypt "$file" "" "true" <<<"Hello World"

    run memo "$file"
    assert_success
    assert_output "No changes detected; skipping re-encryption."

    run _file_is_symmetric "$file"
    assert_success
  )
}
