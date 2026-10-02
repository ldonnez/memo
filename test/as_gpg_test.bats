#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "adds the configured extension if missing" {
  run _as_gpg "$NOTES_DIR/test.md"
  assert_output "$NOTES_DIR/test.md.asc"
}

@test "does not add an extra extension if already present" {
  run _as_gpg "$NOTES_DIR/test.md.asc"
  assert_output "$NOTES_DIR/test.md.asc"
}

@test "keeps an explicitly given .gpg extension" {
  run _as_gpg "$NOTES_DIR/test.md.gpg"
  assert_output "$NOTES_DIR/test.md.gpg"
}

@test "adds no extension at all" {
  run _as_gpg "$NOTES_DIR/test"
  assert_output "$NOTES_DIR/test.asc"
}

@test "uses EXTENSION when set" {
  EXTENSION="gpg" run _as_gpg "$NOTES_DIR/test.md"
  assert_output "$NOTES_DIR/test.md.gpg"
}

@test "keeps an explicitly given .asc extension when EXTENSION is gpg" {
  EXTENSION="gpg" run _as_gpg "$NOTES_DIR/test.md.asc"
  assert_output "$NOTES_DIR/test.md.asc"
}
