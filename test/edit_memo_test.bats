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

@test "successfully creates a new memo with todays date because it does not exist yet" {
  local to_be_created_file
  to_be_created_file=$JOURNAL_NOTES_DIR/$(date +%F).md.gpg

  run edit_memo ""
  assert_success
  assert_output --partial "Encrypted: $to_be_created_file
Cache updated (1 file(s) changed)"
}

@test "successfully detects no changes edits a memo with todays date because it exists already" {
  mkdir -p "$JOURNAL_NOTES_DIR"

  local file
  file="$JOURNAL_NOTES_DIR/$(date +%F).md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run edit_memo ""
  assert_success
  assert_output ""
}

@test "successfully edits existing file" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run edit_memo "$file.gpg"
  assert_success
  assert_output ""
}

@test "successfully creates new file in notes dir ($NOTES_DIR)" {
  local file="new-file-test.md"

  run edit_memo "$file"
  assert_success
  assert_output --partial "Encrypted: $NOTES_DIR/$file.gpg
Cache updated (1 file(s) changed)"
}

@test "fails editting existing file since its not in the notes dir ($NOTES_DIR)" {
  local file
  file="test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run edit_memo "$file.gpg"
  assert_failure
  assert_output "Error: File is not a valid gpg memo in the notes directory."

  # Cleanup
  rm -f "$file" "$file.gpg"
}
