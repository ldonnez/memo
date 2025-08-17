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

@test "unlocks all files in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"
  rm -f "$file"

  mkdir -p "$NOTES_DIR/test_dir"

  local file2="$NOTES_DIR/test_dir/test2.md"
  echo "Hello World" >"$file2"

  gpg_encrypt "$file2" "$file2.gpg"
  rm -f "$file2"

  run unlock "all"
  assert_success

  run file_exists "$file"
  assert_success
  assert_output ""

  run file_exists "$file2"
  assert_success
  assert_output ""
}

@test "unlocks single file in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"
  rm -f "$file"

  run unlock "$file.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run file_exists "$file"
  assert_success

  run file_exists "$file.gpg"
  assert_success
}

@test "unlocks single file by only giving its name in notes dir ($NOTES_DIR)" {
  local file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"
  rm -f "$file"

  run unlock "test.md.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run file_exists "$file"
  assert_success

  run file_exists "$file.gpg"
  assert_success
}

@test "unlocks single file when giving relative path in notes dir ($NOTES_DIR)" {
  mkdir -p "$NOTES_DIR/test_2_dir"

  local file="$NOTES_DIR/test_2_dir/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"
  rm -f "$file"

  run unlock "test_2_dir/test.md.gpg"
  assert_success
  assert_output "Decrypted: $file"

  run file_exists "$file"
  assert_success

  run file_exists "$file.gpg"
  assert_success
}

@test "does not work on a file outside ($NOTES_DIR)" {
  local file="$HOME/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run unlock "$file"
  assert_failure
  assert_output "File not in $NOTES_DIR"

  # Cleanup
  rm -f "$file" "$file.gpg"
}
