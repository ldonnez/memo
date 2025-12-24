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

@test "encrypts all the files and removes the originals in the notes dir ($NOTES_DIR)" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 3" >"$file3"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Encrypted: test.md -> test.md.gpg
Encrypted: test2.md -> test2.md.gpg
Encrypted: test_dir/test2.md -> test_dir/test2.md.gpg"

  run _file_exists "$file1"
  assert_failure

  run _file_exists "$file1.gpg"
  assert_success

  run _file_exists "$file2"
  assert_failure

  run _file_exists "$file2.gpg"
  assert_success

  run _file_exists "$file3"
  assert_failure

  run _file_exists "$file3.gpg"
  assert_success
}

@test "encrypts all the files unless they have an extension that is not supported" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  local file3="$NOTES_DIR/test3.word"
  printf "Hello World 3" >"$file3"

  mkdir -p "$NOTES_DIR/test_dir"
  local file4="$NOTES_DIR/test_dir/test4.md"
  printf "Hello World 3" >"$file4"

  local file5="$NOTES_DIR/test_dir/test5.word"
  printf "Hello World 5" >"$file5"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Extension: word not supported
Extension: word not supported
Encrypted: test.md -> test.md.gpg
Encrypted: test2.md -> test2.md.gpg
Encrypted: test_dir/test4.md -> test_dir/test4.md.gpg"

  run _file_exists "$file1"
  assert_failure

  run _file_exists "$file1.gpg"
  assert_success

  run _file_exists "$file2"
  assert_failure

  run _file_exists "$file2.gpg"
  assert_success

  run _file_exists "$file3"
  assert_success

  run _file_exists "$file4"
  assert_failure

  run _file_exists "$file4.gpg"
  assert_success

  run _file_exists "$file5"
  assert_success
}

@test "encrypts multiple given files in the notes dir ($NOTES_DIR)" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 3" >"$file3"

  run memo_encrypt_files "test2.md" "test_dir/test2.md"
  assert_success
  assert_output "Encrypted: test2.md -> test2.md.gpg
Encrypted: test_dir/test2.md -> test_dir/test2.md.gpg"

  run _file_exists "$file1"
  assert_success

  run _file_exists "$file2"
  assert_failure

  run _file_exists "$file3"
  assert_failure
}

@test "encrypts all the files in test_dir and removes the originals" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 2" >"$file2"

  local file3="$NOTES_DIR/test_dir/test3.md"
  printf "Hello World 3" >"$file3"

  run memo_encrypt_files "test_dir/*"
  assert_success
  assert_output "Encrypted: test_dir/test2.md -> test_dir/test2.md.gpg
Encrypted: test_dir/test3.md -> test_dir/test3.md.gpg"

  run _file_exists "$file1"
  assert_success

  run _file_exists "$file2"
  assert_failure

  run _file_exists "$file3"
  assert_failure
}

@test "Does not encrypt .gpg files" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"

  _gpg_encrypt "$file2.gpg" <<<"Hello World"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"

  _gpg_encrypt "$file3.gpg" <<<"Hello World 3"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Encrypted: test.md -> test.md.gpg"

  run _file_exists "$file1"
  assert_failure

  run _file_exists "$file2.gpg"
  assert_success

  run _file_exists "$file3.gpg"
  assert_success
}

@test "Does not encrypt unsupported extensions" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.word"
  printf "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 3" >"$file3"

  local file4="$NOTES_DIR/test_dir/test3.word"
  printf "Hello World 4" >"$file4"

  cd "$NOTES_DIR"
  run memo_encrypt_files "test_dir/test2.md" "test_dir/test3.word" "test2.word"
  assert_success
  assert_output "Extension: word not supported
Extension: word not supported
Encrypted: test_dir/test2.md -> test_dir/test2.md.gpg"

  run _file_exists "$file1"
  assert_success

  run _file_exists "$file2"
  assert_success

  run _file_exists "$file3"
  assert_failure

  run _file_exists "$file4"
  assert_success
}

@test "ignore files by glob pattern in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  printf "*.txt\n" >"$ignore"

  local mdfile="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  printf "Hello World 2" >"$txtfile"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Ignored (.ignore): .ignore
Ignored (.ignore): test2.txt
Encrypted: test2.md -> test2.md.gpg"

  run _file_exists "$txtfile"
  assert_success
}

@test "ignore files by name in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  printf "test2.txt\n" >"$ignore"

  local mdfile="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  printf "Hello World 2" >"$txtfile"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Ignored (.ignore): .ignore
Ignored (.ignore): test2.txt
Encrypted: test2.md -> test2.md.gpg"

  run _file_exists "$txtfile"
  assert_success
}

@test "ignore directories in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  printf ".git/*\n" >"$ignore"

  mkdir -p "$NOTES_DIR/.git"
  local gitfile="$NOTES_DIR/.git/COMMIT"
  printf "TEST" >"$gitfile"

  local mdfile="$NOTES_DIR/test.md"
  printf "Hello World 2" >"$mdfile"

  run memo_encrypt_files "all"
  assert_success
  assert_output "Ignored (.ignore): .git/COMMIT
Ignored (.ignore): .ignore
Encrypted: test.md -> test.md.gpg"

  run _file_exists "$gitfile"
  assert_success
}

@test "ignore files by glob pattern when excluded with --exclude" {
  local mdfile="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  printf "Hello World 2" >"$txtfile"

  run memo_encrypt_files "all" --exclude "*.txt"
  assert_success
  assert_output "Excluded (--exclude): test2.txt
Encrypted: test2.md -> test2.md.gpg"

  run _file_exists "$txtfile"
  assert_success
}

@test "Shows all actions in dry mode" {
  local file1="$NOTES_DIR/test.md"
  printf "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  printf "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World 3" >"$file3"

  run memo_encrypt_files "all" --dry-run
  assert_success
  assert_output "Would encrypt to: test.md.gpg
Would encrypt to: test2.md.gpg
Would encrypt to: test_dir/test2.md.gpg"
}

@test "Works with single file" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run memo_encrypt_files "test.md"
  assert_success
  assert_output "Encrypted: test.md -> test.md.gpg"

  run _file_exists "$file.md"
  assert_failure
}

@test "Works with single file in subdir" {
  mkdir -p "$NOTES_DIR/test_dir"
  local file="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World" >"$file"

  cd "$NOTES_DIR/test_dir"
  run memo_encrypt_files "test2.md"
  assert_success
  assert_output "Encrypted: test2.md -> test2.md.gpg"

  run _file_exists "$file.md"
  assert_failure
}

@test "Works when giving single file in subdir with path" {
  mkdir -p "$NOTES_DIR/test_dir"
  local file="$NOTES_DIR/test_dir/test2.md"
  printf "Hello World" >"$file"

  run memo_encrypt_files "test_dir/test2.md"
  assert_success
  assert_output "Encrypted: test_dir/test2.md -> test_dir/test2.md.gpg"

  run _file_exists "$file.md"
  assert_failure
}

@test "Does not work on a file outside of notes_dir ($NOTES_DIR)" {
  local file="$HOME/test2.md"
  printf "Hello World" >"$file"

  run memo_encrypt_files "$file"
  assert_failure
  assert_output "File not in $NOTES_DIR"
}

@test "Does not work on a file with an unsupported extension" {
  local file="$NOTES_DIR/test.word"
  printf "Hello World" >"$file"

  run memo_encrypt_files "$file"
  assert_success
  assert_output "Extension: word not supported
Nothing to encrypt."
}
