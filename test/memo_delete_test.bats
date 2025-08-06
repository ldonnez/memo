#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
  rm -f "$CACHE_FILE"
}

@test "deletes the file and does not cache because file does not exist in cache" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run memo_delete --force "$file.gpg"
  assert_success
  assert_output --partial "Deleted: $file.gpg
Cache updated (0 file(s) changed)"
}

@test "does not delete on a file with path outside $NOTES_DIR" {
  local file="$HOME/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run memo_delete "$file.gpg" <<<"y"
  assert_failure
  assert_output "Memo not found: $file.gpg"

  rm -f "$file" "$file.gpg"
}

@test "can delete multiple files" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World" >"$file2"

  gpg_encrypt "$file2" "$file2.gpg"

  memo_cache

  run memo_delete --force "$file.gpg" "$file2.gpg"
  assert_success
  assert_output --partial "Deleted: $file.gpg $file2.gpg
Skipping undecryptable file: $file.gpg
Skipping undecryptable file: $file2.gpg
Cache updated (2 file(s) changed)"
}
