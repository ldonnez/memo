#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  if [[ "$(uname)" == "Linux" ]]; then
    rm -rf "/dev/shm/*"
  fi

  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "returns temp file without .gpg it exists" {
  if [[ "$(uname)" == "Linux" ]]; then
    # Mock /dev/shm as existing
    mkdir -p /dev/shm
  fi

  # Mock file
  touch "$NOTES_DIR/test.md.gpg"

  run _make_tempfile "$NOTES_DIR/test.md.gpg"
  assert_success
  if [[ "$(uname)" == "Linux" ]]; then
    assert_output "/dev/shm/memo-test.md"
  else
    assert_output --regexp "^.*/tmp\.[A-Za-z0-9]+\/memo-test\.md$"
  fi
}

@test "uses mktemp if /dev/shm does not exist" {
  _dir_exists() { return 1; } # mock /dev/shm missing

  run _make_tempfile "2025-01-01.md.gpg"

  assert_output --regexp "^.*/tmp\.[A-Za-z0-9]+\/memo-2025-01-01\.md$"
}
