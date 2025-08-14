#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"

  # mock /dev/shm
  mkdir -p /dev/shm
}

teardown() {
  rm -rf "/dev/shm/*"
}

@test "returns new tmp file with filename as header if file does not exist" {
  local to_be_created_file="test.md"

  run make_or_edit_file "$to_be_created_file"
  assert_success
  assert_output "/dev/shm/memo-$to_be_created_file"

  run cat "/dev/shm/memo-$to_be_created_file"
  assert_output "# test"
}

@test "decrypts existing file in tmpfile" {
  local file
  file="$NOTES_DIR/test.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run make_or_edit_file "$file.gpg"
  assert_success
  assert_output "/dev/shm/memo-test.md"

  run cat "/dev/shm/memo-test.md"
  assert_output "Hello World"
}

@test "decrypts existing current date daily in tmpfile" {
  local date
  date="$(date +%F).md"

  local file
  file="$JOURNAL_NOTES_DIR/$date.md"
  echo "# $date" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run make_or_edit_file "$file.gpg"
  assert_success
  assert_output "/dev/shm/memo-$date.md"

  run cat "/dev/shm/memo-$date.md"
  assert_output "# $date"
}
