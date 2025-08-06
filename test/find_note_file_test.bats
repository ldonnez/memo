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

@test "retuns the path if in notes dir" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run find_note_file "$file"
  assert_success
  assert_output "$file"
}

@test "retuns the path if just giving name when in notes dir" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run find_note_file "test.md"
  assert_success
  assert_output "$file"
}

@test "retuns the path if in subdir of notes dir" {
  mkdir -p "$NOTES_DIR/test_dir"

  local file="$NOTES_DIR/test_dir/test.md"
  printf "Hello World" >"$file"

  run find_note_file "$file"
  assert_success
  assert_output "$file"
}

@test "retuns the path if giving relative path of notes dir" {
  mkdir -p "$NOTES_DIR/test_dir"

  local file="$NOTES_DIR/test_dir/test.md"
  printf "Hello World" >"$file"

  run find_note_file "test_dir/test.md"
  assert_success
  assert_output "$file"
}

@test "retuns the path if giving file name in subdir when working dir is subdir" {
  mkdir -p "$NOTES_DIR/test_dir"

  local file="$NOTES_DIR/test_dir/test.md"
  printf "Hello World" >"$file"

  cd "$NOTES_DIR/test_dir"

  run find_note_file "test.md"
  assert_success
  assert_output "$file"
}

@test "does not return the path if not in notes dir" {
  local file="$HOME/test.md"
  printf "Hello World" >"$file"

  run find_note_file "$file"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  rm -f "$file"
}

@test "does not return the path if file does not exist" {
  local file="i-do-not-exist.md"

  run find_note_file "$file"
  assert_failure
  assert_output "Not found: $file"
}
