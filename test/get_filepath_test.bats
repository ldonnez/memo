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

@test "returns $DEFAULT_FILE path" {
  run _get_filepath ""
  assert_success
  assert_output "$NOTES_DIR/$DEFAULT_FILE"
}

@test "returns <current_date>.md path" {
  run _get_filepath "today"
  assert_success
  assert_output "$NOTES_DIR/$(date +%F).md"
}

@test "returns $NOTES_DIR/test.md path" {
  run _get_filepath "test.md"
  assert_success
  assert_output "$NOTES_DIR/test.md"
}

@test "returns $NOTES_DIR/test/test.md path" {
  run _get_filepath "test/test.md"
  assert_success
  assert_output "$NOTES_DIR/test/test.md"
  [ -d "$NOTES_DIR/test" ]
}

@test "returns $NOTES_DIR/test_pwd/pwd.md path" {
  mkdir -p "$NOTES_DIR/test_pwd"

  cd "$NOTES_DIR/test_pwd"
  run _get_filepath "pwd.md"
  assert_success
  assert_output "$NOTES_DIR/test_pwd/pwd.md"
}

@test "returns $NOTE_DIR/$DEFAULT_FILE path when inside $NOTES_DIR" {
  cd "$NOTES_DIR"
  run _get_filepath ""
  assert_success
  assert_output "$NOTES_DIR/$DEFAULT_FILE"
}

@test "fails with unsupported extension" {
  run _get_filepath "test/test.word"
  assert_failure
  assert_output "Extension: word not supported"
}
