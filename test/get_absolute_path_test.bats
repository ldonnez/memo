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

@test "returns absolute path of given file" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run _get_absolute_path "$file"
  assert_success

  assert_output "$file"
}

@test "returns absolute path of given relative path" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  cd "$NOTES_DIR"

  run _get_absolute_path "test.md"
  assert_success

  assert_output "$file"
}

@test "returns absolute path of given relative path when subdir" {
  mkdir -p "$NOTES_DIR/test_dir"

  local file="$NOTES_DIR/test_dir/test.md"
  printf "Hello World" >"$file"

  cd "$NOTES_DIR"

  run _get_absolute_path "test_dir/test.md"
  assert_success

  assert_output "$file"
}

@test "returns absolute path of original file when given a symlink" {
  local original_file="$NOTES_DIR/test_original.md"
  printf "Hello World" >"$original_file"

  local symlink_file="$NOTES_DIR/test.md"
  ln -sf "$original_file" "$symlink_file"

  # Run the function with the symlink
  run _get_absolute_path "$symlink_file"
  assert_success

  assert_output "$original_file"
}
