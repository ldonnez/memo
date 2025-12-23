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
}

@test "successfully edits existing file" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo "$file.gpg"
  assert_success
  assert_output ""
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
  file="test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo "$file.gpg"
  assert_failure
  assert_output "Error: File is not a valid gpg memo in the notes directory."

  # Cleanup
  rm -f "$file" "$file.gpg"
}

@test "fails creating new file with unspported extension" {
  local file="new-file-test.word"

  run memo "$file"
  assert_failure
  assert_output "Extension: word not supported"
}
