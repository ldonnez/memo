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

@test "returns 0 when file is in notes_dir" {
  local input_path="$NOTES_DIR/test.md"
  printf "Hello World" >"$input_path"

  run _is_in_notes_dir "$input_path"
  assert_success
}

@test "returns 1 when file is not in notes_dir" {
  local input_path="$HOME/test.md"
  printf "Hello World" >"$input_path"

  run _is_in_notes_dir "$input_path"
  assert_failure
}

@test "returns 1 for a sibling dir that starts with the notes dir name" {
  local sibling="${NOTES_DIR}-backup"
  mkdir -p "$sibling"
  printf "Hello World" >"$sibling/test.md"

  run _is_in_notes_dir "$sibling/test.md"
  assert_failure

  rm -rf "$sibling"
}

@test "returns 0 for a subdir of the notes dir" {
  mkdir -p "$NOTES_DIR/sub"
  printf "Hello World" >"$NOTES_DIR/sub/test.md"

  run _is_in_notes_dir "$NOTES_DIR/sub/test.md"
  assert_success
}
