#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEMP="$(mktemp -d)"

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "$TEMP"
}

@test "Creates missing dirs and ensures CACHE_DIR is only writable for current user" {
  # Run in subshell to prevent collision in other tests
  (
    local NOTES_DIR="$TEMP/test_notes"
    local JOURNAL_NOTES_DIR="$NOTES_DIR/journal"
    local CACHE_DIR="$TEMP/cache"

    create_dirs

    assert_equal "" "$([[ -d "$NOTES_DIR" ]])"
    assert_equal "" "$([[ -d "$JOURNAL_NOTES_DIR" ]])"
    assert_equal "" "$([[ -d "$CACHE_DIR" ]])"

    assert_equal "700" "$(stat -c "%a" "$CACHE_DIR")"
  )
}
