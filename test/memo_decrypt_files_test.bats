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

@test "decrypts all files in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World\n" >"$file2"
  _gpg_encrypt "$file2" "$file2.gpg"

  rm -f "$file2"

  run memo_decrypt_files "all"
  assert_success

  run _file_exists "$file"
  assert_success
  assert_output ""

  run _file_exists "$file2"
  assert_success
  assert_output ""
}

@test "can decrypt multiple files" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2\n" >"$file2"

  _gpg_encrypt "$file2" "$file2.gpg"

  rm -f "$file2"

  local file3="$NOTES_DIR/test3.md"
  printf "Hello World 3\n" >"$file3"

  _gpg_encrypt "$file3" "$file3.gpg"

  rm -f "$file3"

  run memo_decrypt_files "test2.md.gpg" "test3.md.gpg"
  assert_success
  assert_output "Decrypted: $file2
Decrypted: $file3"

  run _file_exists "$file2"
  assert_success

  run _file_exists "$file3"
  assert_success
}

@test "decrypts all files in test_dir/* ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 2\n" >"$file2"

  _gpg_encrypt "$file2" "$file2.gpg"

  rm -f "$file2"

  run memo_decrypt_files "test_dir/*"
  assert_success

  run _file_exists "$file"
  assert_failure

  run _file_exists "$file2"
  assert_success
}

@test "decrypts single file in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  run memo_decrypt_files "$file.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run _file_exists "$file"
  assert_success

  run _file_exists "$file.gpg"
  assert_failure
}

@test "decrypts single file by only giving its name in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"
  rm -f "$file"

  run memo_decrypt_files "test.md.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run _file_exists "$file"
  assert_success

  run _file_exists "$file.gpg"
  assert_failure
}

@test "decrypts single file when giving relative path in notes dir ($NOTES_DIR)" {
  mkdir -p "$NOTES_DIR/test_2_dir"
  local file="$NOTES_DIR/test_2_dir/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  rm -f "$file"

  run memo_decrypt_files "test_2_dir/test.md.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run _file_exists "$file"
  assert_success

  run _file_exists "$file.gpg"
  assert_failure
}

@test "does not work on a file outside ($NOTES_DIR)" {
  local file="$HOME/test.md"
  printf "Hello World\n" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run memo_decrypt_files "$file"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  # Cleanup
  rm -f "$file" "$file.gpg"
}
