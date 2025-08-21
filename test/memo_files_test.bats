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

@test "should correctly find and edit a .gpg file" {
  # Setup: Create a temporary directory and a test file
  local file="$NOTES_DIR/file.md"
  printf "Hello world" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  # Mock rg
  rg() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  # Mock fzf command
  fzf() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  # Mock for edit_memo
  edit_memo() {
    if [[ "$1" == "$NOTES_DIR/file.gpg" ]]; then
      printf "edit_memo called with correct file\n"
      return 0
    else
      printf "edit_memo called with wrong file\n" >&2
      return 1
    fi
  }

  run memo_files

  assert_success
  assert_output "edit_memo called with correct file"
}
