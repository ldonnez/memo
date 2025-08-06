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

@test "returns daily notes path with todays date as filename if empty arg" {
  local to_be_created_file
  to_be_created_file=$JOURNAL_NOTES_DIR/$(date +%F).md

  run get_target_filepath ""
  assert_success
  assert_output "$to_be_created_file"
}

@test "returns full path if note is in notes dir ($NOTES_DIR)" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run get_target_filepath "$file.gpg"
  assert_success
  assert_output "$file.gpg"
}

@test "fails because existing file is not in notes dir" {
  local file
  file="not-in-notes-dir.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run get_target_filepath "$file.gpg"
  assert_failure
  assert_output "Error: File is not a valid gpg memo in the notes directory."

  rm -f "$file" "$file.gpg"
}

@test "returns new file path in notes dir when file does not exist yet" {
  local file="new-file.md"

  run get_target_filepath "$file"
  assert_success
  assert_output "$NOTES_DIR/$file"
}
