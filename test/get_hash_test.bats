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

@test "returns hash of the content of the file" {
  local file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  run get_hash "$file"
  assert_success
  assert_output "b10a8db164e0754105b7a99be72e3fe5"
}
