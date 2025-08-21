#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "correctly sets default values" {
  # Run in subshell to prevent collision in other tests
  (
    local script_path="/path/to/script"
    local KEY_IDS
    local NOTES_DIR
    local JOURNAL_NOTES_DIR
    local EDITOR_CMD
    local CACHE_DIR
    local CACHE_FILE
    local CACHE_BUILDER_BIN

    set_default_values "$script_path"
    assert_equal "$KEY_IDS" ""
    assert_equal "$NOTES_DIR" "$HOME/notes"
    assert_equal "$JOURNAL_NOTES_DIR" "$NOTES_DIR/journal"
    assert_equal "$EDITOR_CMD" "nano"
    assert_equal "$CACHE_DIR" "$HOME/.cache/memo"
    assert_equal "$CACHE_FILE" "$CACHE_DIR/notes.cache"
    assert_equal "$CACHE_BUILDER_BIN" "$script_path/bin/cache_builder"
  )
}
