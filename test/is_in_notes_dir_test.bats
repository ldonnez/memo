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
