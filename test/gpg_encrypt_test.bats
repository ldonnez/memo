#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "encrypts file to same path when no output_path (second arg) is given" {
  local input_path="$NOTES_DIR/test.md"
  echo "Hello World" >"$input_path"

  run gpg_encrypt "$input_path" "$input_path.gpg"
  assert_success
  assert_output "Encrypted: $input_path.gpg"

  run file_exists "$input_path.gpg"
  assert_success

  # Cleanup
  rm -f "$input_path" "$input_path"
}

@test "encrypts file to given output_path" {
  local input_path="$NOTES_DIR/test.md"
  echo "Hello World" >"$input_path"

  local output_path="$NOTES_DIR/test.md"

  run gpg_encrypt "$input_path" "$output_path.gpg"
  assert_success
  assert_output "Encrypted: $output_path.gpg"

  run file_exists "$output_path.gpg"
  assert_success

  # Cleanup
  rm -f "$input_path" "$output_path"
}
