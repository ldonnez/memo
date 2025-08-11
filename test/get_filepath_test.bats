#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=src/memo.sh
  source "memo.sh"
}

@test "returns $DAILY_NOTES_DIR/<current_date>.md path" {
  run get_filepath "today"
  assert_output "$DAILY_NOTES_DIR/$(date +%F).md"
}

@test "returns $NOTES_DIR/test.md path" {
  run get_filepath "test.md"
  assert_output "$NOTES_DIR/test.md"
}

@test "returns $NOTES_DIR/test/test.md path" {
  run get_filepath "test/test.md"
  assert_output "$NOTES_DIR/test/test.md"
  [ -d "$NOTES_DIR/test" ]
}

@test "returns $NOTES_DIR/test_pwd/pwd.md path" {
  mkdir -p "$NOTES_DIR/test_pwd"

  cd "$NOTES_DIR/test_pwd"
  run get_filepath "pwd.md"
  assert_output "$NOTES_DIR/test_pwd/pwd.md"
}
