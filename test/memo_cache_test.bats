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

@test "caches all current files when giving no files" {
  run _file_exists "$_CACHE_FILE"
  assert_failure

  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  _gpg_encrypt "$file2" "$file2.gpg"

  run memo_cache
  assert_success
  assert_output --partial "Updated files in cache:
- test.md.gpg
- test2.md.gpg"
}

@test "caches files incrementally" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  memo_cache

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  _gpg_encrypt "$file2" "$file2.gpg"

  run memo_cache
  assert_success
  assert_output --partial "Updated files in cache:
- test2.md.gpg"
}

@test "does not cache when no changes" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  memo_cache

  run memo_cache
  assert_success
  assert_output "No files updated in cache"
}

@test "does cache when file has changes" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  memo_cache

  printf "Changed" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo_cache
  assert_success
  assert_output "Updated files in cache:
- test.md.gpg"
}
