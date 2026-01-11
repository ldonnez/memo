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
  to_be_created_file="$NOTES_DIR/$CAPTURE_FILE.gpg"

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

@test "successfully creates a new memo with $CAPTURE_FILE.gpg as filename when it does not exist" {
  (
    local CAPTURE_FILE="$CAPTURE_FILE.gpg"
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

@test "successfully edits existing file and do not trigger encryption" {
  local file
  file="$NOTES_DIR/test.md.gpg"

  _gpg_encrypt "$file" <<<"Hello World"

  run memo "$file"
  assert_success
  assert_output "No changes detected; skipping re-encryption."
}

@test "edits existing file and triggers encryption" {
  # Run in subshell to avoid collision with other tests
  (
    local file="$NOTES_DIR/test.md.gpg"

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

  run cat "$NOTES_DIR/$file.gpg"
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

@test "fails creating new file with unspported extension" {
  local file="new-file-test.word"

  run memo "$file"
  assert_failure
  assert_output "Extension: word not supported"
}
