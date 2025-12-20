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

@test "Creates missing dirs" {
  # Run in subshell to prevent collision in other tests
  (
    local NOTES_DIR="$TEMP/test_notes"

    _create_dirs

    assert_equal "" "$([[ -d "$NOTES_DIR" ]])"
  )
}
