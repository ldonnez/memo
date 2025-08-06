#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns YYYY-MM-DD of today's date when today is given" {
  run _determine_filename "today"
  assert_output "$(date +%F).md"
}

@test "returns YYYY-MM-DD.md of yesterdays date when yesterday is given" {
  run _determine_filename "yesterday"
  assert_output "$(date -d "yesterday" +%F 2>/dev/null || date -v-1d +%F).md"
}

@test "returns YYYY-MM-DD.md of tomorrows date when tomorrow is given" {
  run _determine_filename "tomorrow"
  assert_output "$(date -d "tomorrow" +%F 2>/dev/null || date -v+1d +%F).md"
}

@test "returns test.md when test.md is given" {
  run _determine_filename "test.md"
  assert_output "test.md"
}

@test "returns YYYY-MM-DD.md when 2025-01-01 is given" {
  run _determine_filename "2025-01-01"
  assert_output "2025-01-01.md"
}

@test "returns test.md when test is given" {
  run _determine_filename "test"
  assert_output "test.md"
}

@test "fails when filename with unsupported extension is given" {
  run _determine_filename "test.word"
  assert_failure
  assert_output "Extension: word not supported"
}
