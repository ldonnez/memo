#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns temp file without .gpg in /dev/shm if it exists" {
  # Mock /dev/shm as existing
  mkdir -p /dev/shm

  # Mock file
  touch "$NOTES_DIR/test.md.gpg"

  run make_tempfile "$NOTES_DIR/test.md.gpg"
  assert_success
  assert_output "/dev/shm/memo-test.md"
}

@test "uses mktemp if /dev/shm does not exist" {
  dir_exists() { return 1; } # mock /dev/shm missing

  run make_tempfile "2025-01-01.md.gpg"

  assert_output --regexp "^/tmp/tmp.*/memo-2025-01-01.md$"
}
