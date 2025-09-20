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
  rm -f "$_CACHE_FILE"
}

@test "deletes the file and does not cache because file does not exist in cache" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo_delete --force "$file.gpg"
  assert_success
  assert_output --partial "Deleted: $file.gpg
No files updated in cache"
}

@test "does not delete on a file with path outside $NOTES_DIR" {
  local file="$HOME/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo_delete "$file.gpg" <<<"y"
  assert_failure
  assert_output "Memo not found: $file.gpg"

  rm -f "$file" "$file.gpg"
}

@test "can delete multiple files" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World" >"$file2"

  _gpg_encrypt "$file2" "$file2.gpg"

  memo_cache

  run memo_delete --force "$file.gpg" "$file2.gpg"
  assert_success
  assert_output "Deleted: $file.gpg $file2.gpg
Updated files in cache:
- test.md.gpg
- test2.md.gpg"
}
