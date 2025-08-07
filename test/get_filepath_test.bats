#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=src/memo.sh
  source "memo.sh"
}

@test "returns $DAILY_NOTES_DIR path" {
  run get_filepath "today"
  assert_output "$DAILY_NOTES_DIR/$(date +%F).md"
}

@test "returns $NOTES_DIR path" {
  run get_filepath "test.md"
  assert_output "$NOTES_DIR/test.md"
}
