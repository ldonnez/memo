#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns YYYY-MM-DD of today's date when today is given" {
  run determine_filename "today"
  assert_output "$(date +%F).md"
}

@test "returns YYYY-MM-DD.md of yesterdays date when yesterday is given" {
  run determine_filename "yesterday"
  assert_output "$(date -d yesterday +%F).md"
}

@test "returns YYYY-MM-DD.md of tomorrows date when tomorrow is given" {
  run determine_filename "tomorrow"
  assert_output "$(date -d tomorrow +%F).md"
}

@test "returns test.md when test.md is given" {
  run determine_filename "test.md"
  assert_output "test.md"
}

@test "returns YYYY-MM-DD.md when 2025-01-01 is given" {
  run determine_filename "2025-01-01"
  assert_output "2025-01-01.md"
}

@test "get_filepath returns $JOURNAL_NOTES_DIR path" {
  run get_filepath "today"
  assert_output "$JOURNAL_NOTES_DIR/$(date +%F).md"
}

@test "get_filepath returns $NOTES_DIR path" {
  run get_filepath "test.md"
  assert_output "$NOTES_DIR/test.md"
}
