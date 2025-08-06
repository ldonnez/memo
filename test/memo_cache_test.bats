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

@test "caches all current files when giving no files" {
  run file_exists "$CACHE_FILE"
  assert_failure

  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  gpg_encrypt "$file2" "$file2.gpg"

  run memo_cache
  assert_success
  assert_output --partial "Cache updated (2 file(s) changed)"
}

@test "caches files incrementally" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  gpg_encrypt "$file2" "$file2.gpg"

  run memo_cache
  assert_success
  assert_output --partial "Cache updated (1 file(s) changed)"
}

@test "does not cache when no changes" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  run memo_cache
  assert_success
  assert_output --partial "Cache updated (0 file(s) changed)"
}

@test "does cache when file has changes" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  printf "Changed" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run memo_cache
  assert_success
  assert_output --partial "Cache updated (1 file(s) changed)"
}
