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
    local GPG_RECIPIENTS
    local NOTES_DIR
    local EDITOR_CMD
    local DEFAULT_EXTENSION
    local SUPPORTED_EXTENSIONS
    local CAPTURE_FILE
    local DEFAULT_IGNORE
    local DEFAULT_GIT_COMMIT

    _set_default_values
    assert_equal "$GPG_RECIPIENTS" ""
    assert_equal "$NOTES_DIR" "$HOME/notes"
    # Use readlink -f to follow symlinks here since macOS symlinks temp from /var/... to /private/var/
    assert_equal "$EDITOR_CMD" "nano"
    assert_equal "$DEFAULT_EXTENSION" "md"
    assert_equal "$SUPPORTED_EXTENSIONS" "md,org,txt"
    assert_equal "$CAPTURE_FILE" "inbox.md"
    assert_equal "$DEFAULT_IGNORE" ".ignore,.git/*,.githooks/*,.DS_store,.gitignore,.gitattributes"
    assert_equal "$DEFAULT_GIT_COMMIT" "$(hostname): sync $(date '+%Y-%m-%d %H:%M:%S')"
  )
}
