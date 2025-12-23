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

@test "prepends $CAPTURE_HEADER to file when file has at least 3 lines" {
  local file
  file="$NOTES_DIR/test.md"

  printf "\n\n\n" >>"$file"

  run _prepend_header "$file"
  assert_success

  run cat "$file"
  assert_output "

$CAPTURE_HEADER"
}

@test "does not prepend $CAPTURE_HEADER to file when it's empty" {
  (
    local CAPTURE_HEADER
    local file
    file="$NOTES_DIR/test.md"

    run _prepend_header "$file"
    assert_success

    run _file_exists "$file"
    assert_failure
  )
}

@test "does not prepend $CAPTURE_HEADER to file when file has not at least 3 lines" {
  local file
  file="$NOTES_DIR/test.md"

  touch "$file"

  run _prepend_header "$file"
  assert_success

  run cat "$file"
  assert_output ""
}
