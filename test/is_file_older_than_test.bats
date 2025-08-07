#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=src/memo.sh
  source "memo.sh"
}

@test "returns success when file is older" {
  local file1="$NOTES_DIR/test1.md"
  echo "Hello World" >"$file1"

  sleep 1

  local file2="$NOTES_DIR/test2.md"
  echo "Hello World" >"$file2"

  run is_file_older_than "$file1" "$file2"
  assert_success

  # Cleanup
  rm -f "$file1" "$file2"
}

@test "returns failure when file is not older" {
  local file1="$NOTES_DIR/test1.md"
  echo "Hello World" >"$file1"

  local file2="$NOTES_DIR/test1.md"
  echo "Hello World" >"$file2"

  run is_file_older_than "$file1" "$file2"
  assert_failure

  # Cleanup
  rm -f "$file1" "$file2"
}
