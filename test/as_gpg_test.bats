#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns file with .gpg extension if missing" {
  run _as_gpg "$NOTES_DIR/test.md"
  assert_output "$NOTES_DIR/test.md.gpg"
}

@test "does not add extra .gpg extension if already present" {
  run _as_gpg "$NOTES_DIR/test.md.gpg"
  assert_output "$NOTES_DIR/test.md.gpg"
}
