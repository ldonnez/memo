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

@test "returns md extension" {
  run _get_extension "test.md"
  assert_output "md"
}

@test "returns multiple .tar.gz extension" {
  run _get_extension "test.tar.gz"
  assert_output "tar.gz"
}

@test "returns empty string when file has no extension" {
  run _get_extension "test"
  assert_output ""
}
