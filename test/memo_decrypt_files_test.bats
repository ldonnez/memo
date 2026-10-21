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

  run memo_decrypt_files --delete-source "all"
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

  run memo_decrypt_files --delete-source "test2.md.gpg" "test3.md.gpg"
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

  run memo_decrypt_files --delete-source "test_dir/*"
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

  run memo_decrypt_files --delete-source "$file.gpg"
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

  run memo_decrypt_files --delete-source "test.md.gpg"
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

  run memo_decrypt_files --delete-source "test_2_dir/test.md.gpg"
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

  run memo_decrypt_files --delete-source "$file.gpg"
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

  run memo_decrypt_files --delete-source "$encrypted"
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

  run memo_decrypt_files --delete-source "../outside.md.gpg"
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

  run memo_decrypt_files --delete-source "outside.md.gpg"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  [ -f "$outside" ]
  [ ! -e "$HOME/outside.md" ]
  rm -f "$link" "$outside"
}

@test "decrypts multiple files in one GPG invocation" {
  local file1="$NOTES_DIR/batch1.md"
  local file2="$NOTES_DIR/test_dir/batch2.md"
  mkdir -p "$NOTES_DIR/test_dir"

  _gpg_encrypt "$file1.asc" <<<"Batch one"
  _gpg_encrypt "$file2.gpg" <<<"Batch two"
  rm -f "$file1" "$file2"

  run memo_decrypt_files --delete-source "$file1.asc" "$file2.gpg"
  assert_success
  assert_output "Decrypted: $file1
Decrypted: $file2"

  run cat "$file1"
  assert_output "Batch one"
  run cat "$file2"
  assert_output "Batch two"
  [ ! -e "$file1.asc" ]
  [ ! -e "$file2.gpg" ]
}

@test "failed batch decryption keeps all encrypted source files" {
  local file1="$NOTES_DIR/valid.md.gpg"
  local file2="$NOTES_DIR/invalid.md.asc"
  _gpg_encrypt "$file1" <<<"Valid content"
  printf 'not an encrypted message\n' >"$file2"

  run memo_decrypt_files --delete-source "$file1" "$file2"
  assert_success
  assert_output --partial "Failed to decrypt: $file1"
  assert_output --partial "Failed to decrypt: $file2"

  [ -f "$file1" ]
  [ -f "$file2" ]
  # GPG may have successfully decrypted one input before another failed.
  if [ -e "$NOTES_DIR/valid.md" ]; then
    [ "$(cat "$NOTES_DIR/valid.md")" = "Valid content" ]
  fi
  [ ! -e "$NOTES_DIR/invalid.md" ]
}

@test "batch decryption failure does not delete existing plaintext outputs" {
  local file1="$NOTES_DIR/existing.md.gpg"
  local file2="$NOTES_DIR/invalid.md.gpg"
  printf 'existing plaintext\n' >"$NOTES_DIR/existing.md"
  printf 'encrypted placeholder\\n' >"$file1"
  printf 'encrypted placeholder\\n' >"$file2"

  _gpg_run() {
    return 1
  }

  run memo_decrypt_files --delete-source "$file1" "$file2"
  assert_success
  assert_output --partial "Failed to decrypt: $file1"
  assert_output --partial "Failed to decrypt: $file2"

  [ "$(cat "$NOTES_DIR/existing.md")" = "existing plaintext" ]
  [ -f "$file1" ]
  [ -f "$file2" ]
}

@test "overwrites existing plaintext outputs during batch decryption" {
  local file1="$NOTES_DIR/existing.md.gpg"
  local file2="$NOTES_DIR/other.md.gpg"
  printf 'old content\n' >"$NOTES_DIR/existing.md"
  _gpg_encrypt "$file1" <<<"Encrypted first"
  _gpg_encrypt "$file2" <<<"Encrypted second"

  run memo_decrypt_files --delete-source "$file1" "$file2"
  assert_success
  assert_output "Overwriting existing decryption output: $NOTES_DIR/existing.md
Decrypted: $NOTES_DIR/existing.md
Decrypted: $NOTES_DIR/other.md"

  [ "$(cat "$NOTES_DIR/existing.md")" = "Encrypted first" ]
  [ "$(cat "$NOTES_DIR/other.md")" = "Encrypted second" ]
  [ ! -e "$file1" ]
  [ ! -e "$file2" ]
}

@test "rejects batch decryption when multiple inputs target the same plaintext path" {
  local file1="$NOTES_DIR/duplicate.md.gpg"
  local file2="$NOTES_DIR/duplicate.md.asc"
  _gpg_encrypt "$file1" <<<"First"
  _gpg_encrypt "$file2" <<<"Second"

  run memo_decrypt_files --delete-source "$file1" "$file2"
  assert_failure
  assert_output "Multiple encrypted files target the same output: $NOTES_DIR/duplicate.md"

  [ -f "$file1" ]
  [ -f "$file2" ]
  [ ! -e "$NOTES_DIR/duplicate.md" ]
}

@test "keeps encrypted source by default" {
  local file="$NOTES_DIR/keep-source.md"
  _gpg_encrypt "$file.asc" <<<"Encrypted content"

  run memo_decrypt_files "$file.asc"
  assert_success
  assert_output "Decrypted: $file"

  [ -f "$file" ]
  [ -f "$file.asc" ]
  [ "$(cat "$file")" = "Encrypted content" ]
}
