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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

  rm -f "$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"
  _gpg_encrypt "$file2.gpg" <<<"Hello World\n"

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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

  rm -f "$file"

  local file2="$NOTES_DIR/test2.md"

  _gpg_encrypt "$file2.gpg" <<<"Hello World 2\n"

  rm -f "$file2"

  local file3="$NOTES_DIR/test3.md"

  _gpg_encrypt "$file3.gpg" <<<"Hello World 3\n"

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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

  rm -f "$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"

  _gpg_encrypt "$file2.gpg" <<<"Hello World 2\n"

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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"
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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

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

  _gpg_encrypt "$file.gpg" <<<"Hello World\n"

  run memo_decrypt_files "$file.gpg"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  # Cleanup
  rm -f "$file" "$file.gpg"
}

@test "removes partial plaintext and its private temp directory after failed decryption" {
  local encrypted="$NOTES_DIR/partial.md.gpg"
  local marker="$TEST_HOME/decrypt-temp-path"

  printf 'encrypted placeholder\n' >"$encrypted"

  _gpg_decrypt() {
    printf 'partial plaintext\n' >"$2"
    printf '%s' "$2" >"$marker"
    return 1
  }

  run memo_decrypt_files "$encrypted"
  assert_success
  assert_output "Failed to decrypt: $encrypted"

  local tmp
  tmp="$(cat "$marker")"
  [ ! -e "$tmp" ]
  [ ! -d "${tmp%/*}" ]
  [ -f "$encrypted" ]
  [ ! -e "$NOTES_DIR/partial.md" ]
}

@test "does not decrypt a glob that escapes the notes directory" {
  local outside="$HOME/outside.md.gpg"
  printf 'encrypted placeholder\n' >"$outside"

  run memo_decrypt_files "../outside.md.gpg"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  [ -f "$outside" ]
  [ ! -e "$HOME/outside.md" ]
  rm -f "$outside"
}

@test "does not decrypt a symlinked note that points outside the notes directory" {
  local outside="$HOME/outside.md.gpg"
  local link="$NOTES_DIR/outside.md.gpg"
  printf 'encrypted placeholder\n' >"$outside"
  ln -s "$outside" "$link"

  run memo_decrypt_files "outside.md.gpg"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  [ -f "$outside" ]
  [ ! -e "$HOME/outside.md" ]
  rm -f "$link" "$outside"
}
