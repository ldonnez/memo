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

@test "should correctly find and edit a .gpg file" {
  # Setup: Create a temporary directory and a test file
  local file="$NOTES_DIR/file.md"

  _gpg_encrypt "$file" <<<"Hello world"

  # Mock rg
  # shellcheck disable=SC2329
  rg() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  # Mock fzf command
  # shellcheck disable=SC2329
  fzf() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  # Mock for memo
  memo() {
    if [[ "$1" == "$NOTES_DIR/file.gpg" ]]; then
      printf "memo called with correct file\n"
      return 0
    else
      printf "memo called with wrong file\n" >&2
      return 1
    fi
  }

  run memo_files

  assert_success
  assert_output "memo called with correct file"
}

@test "Returns error because rg does not exist" {
  # Mock fzf command
  # shellcheck disable=SC2329
  fzf() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  run memo_files
  assert_failure
  assert_output "Error: gpg, rg and fzf are required for memo_files"
}

@test "Returns error because fzf does not exist" {
  # Mock rg
  # shellcheck disable=SC2329
  rg() {
    printf "%s/file.gpg" "$NOTES_DIR"
  }

  run memo_files
  assert_failure
  assert_output "Error: gpg, rg and fzf are required for memo_files"
}
