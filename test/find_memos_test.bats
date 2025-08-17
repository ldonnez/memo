#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
}

@test "find_memos should correctly find and edit a .gpg file" {
  # Setup: Create a temporary directory and a test file
  local file="$NOTES_DIR/file.md"
  echo "Hello world" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  # Mock rg
  rg() {
    echo "$NOTES_DIR/file.gpg"
  }

  # Mock fzf command
  fzf() {
    echo "$NOTES_DIR/file.gpg"
  }

  # Mock for edit_memo
  edit_memo() {
    if [[ "$1" == "$NOTES_DIR/file.gpg" ]]; then
      echo "edit_memo called with correct file"
      return 0
    else
      echo "edit_memo called with wrong file" >&2
      return 1
    fi
  }

  run find_memos

  assert_success
  assert_output "edit_memo called with correct file"
}
