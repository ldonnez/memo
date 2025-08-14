#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "decrypts file to given output path" {
  local input_path="$NOTES_DIR/test.md"
  echo "Hello World" >"$input_path"

  gpg_encrypt "$input_path" "$input_path.gpg"

  run gpg_decrypt "$input_path.gpg" "$input_path.md"
  assert_success

  # Cleanup
  rm -f "$input_path.gpg" "$input_path.md"
}
