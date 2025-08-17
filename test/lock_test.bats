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

@test "encrypts all the files and removes the originals in the notes dir ($NOTES_DIR)" {
  local file1="$NOTES_DIR/test.md"
  echo "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World 3" >"$file3"

  run lock "all"
  assert_success
  assert_output "Encrypted: $file2
Encrypted: $file1
Encrypted: $file3"

  run file_exists "$file1"
  assert_failure

  run file_exists "$file2"
  assert_failure

  run file_exists "$file3"
  assert_failure
}

@test "Does not encrypt .gpg files" {
  local file1="$NOTES_DIR/test.md"
  echo "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$file2"

  gpg_encrypt "$file2" "$file2.gpg"
  rm -f "$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World 3" >"$file3"

  gpg_encrypt "$file3" "$file3.gpg"
  rm -f "$file3"

  run lock "all"
  assert_success
  assert_output "Encrypted: $file1"

  run file_exists "$file1"
  assert_failure

  run file_exists "$file2.gpg"
  assert_success

  run file_exists "$file3.gpg"
  assert_success
}

@test "ignore files by glob pattern in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  echo "*.txt" >"$ignore"

  local mdfile="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  echo "Hello World 2" >"$txtfile"

  run lock "all"
  assert_success
  assert_output "Ignored (.ignore): .ignore
Ignored (.ignore): test2.txt
Encrypted: $mdfile"

  run file_exists "$txtfile"
  assert_success

  # Cleanup
  rm -f "$ignore" "$mdfile" "$mdfile.gpg" "$txtfile"
}

@test "ignore files by name in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  echo "test2.txt" >"$ignore"

  local mdfile="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  echo "Hello World 2" >"$txtfile"

  run lock "all"
  assert_success
  assert_output "Ignored (.ignore): .ignore
Ignored (.ignore): test2.txt
Encrypted: $mdfile"

  run file_exists "$txtfile"
  assert_success
}

@test "ignore directories in .ignore" {
  local ignore="$NOTES_DIR/.ignore"
  echo ".git/*" >"$ignore"

  mkdir -p "$NOTES_DIR/.git"
  local gitfile="$NOTES_DIR/.git/COMMIT"
  echo "TEST" >"$gitfile"

  local mdfile="$NOTES_DIR/test.md"
  echo "Hello World 2" >"$mdfile"

  run lock "all"
  assert_success
  assert_output "Ignored (.ignore): .git/COMMIT
Ignored (.ignore): .ignore
Encrypted: $mdfile"

  run file_exists "$gitfile"
  assert_success
}

@test "ignore files by glob patter when excluded with --exclude" {
  local mdfile="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$mdfile"

  local txtfile="$NOTES_DIR/test2.txt"
  echo "Hello World 2" >"$txtfile"

  run lock "all" --exclude "*.txt"
  assert_success
  assert_output "Excluded (--exclude): test2.txt
Encrypted: $mdfile"

  run file_exists "$txtfile"
  assert_success
}

@test "Shows all actions in dry mode" {
  local file1="$NOTES_DIR/test.md"
  echo "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  echo "Hello World 2" >"$file2"

  mkdir -p "$NOTES_DIR/test_dir"
  local file3="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World 3" >"$file3"

  run lock "all" --dry-run
  assert_success
  assert_output "Would encrypt: $file2
Would encrypt: $file1
Would encrypt: $file3"
}

@test "Works with single file" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  run lock "test.md"
  assert_success
  assert_output "Encrypted: test.md"

  run file_exists "$file.md"
  assert_failure

  # Cleanup
  rm -f "$file.gpg"
}

@test "Works with single file in subdir" {
  mkdir -p "$NOTES_DIR/test_dir"
  local file="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World" >"$file"

  cd "$NOTES_DIR/test_dir"
  run lock "test2.md"
  assert_success
  assert_output "Encrypted: test_dir/test2.md"

  run file_exists "$file.md"
  assert_failure
}

@test "Works when giving single file in subdir with path" {
  mkdir -p "$NOTES_DIR/test_dir"
  local file="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World" >"$file"

  run lock "test_dir/test2.md"
  assert_success
  assert_output "Encrypted: test_dir/test2.md"

  run file_exists "$file.md"
  assert_failure
}

@test "Does not work on a file outside of notes_dir ($NOTES_DIR)" {
  local file="$HOME/test2.md"
  echo "Hello World" >"$file"

  run lock "$file"
  assert_failure
  assert_output "File not in $NOTES_DIR"
}
