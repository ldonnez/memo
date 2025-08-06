#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"

  if [[ "$(uname)" == "Linux" ]]; then
    # mock /dev/shm
    mkdir -p /dev/shm
  fi
}

teardown() {
  if [[ "$(uname)" == "Linux" ]]; then
    rm -rf "/dev/shm/*"
  fi

  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "returns new tmp file with filename as header if file does not exist" {
  local to_be_created_file="test.md"

  run _make_or_edit_file "$to_be_created_file"
  assert_success

  if [[ "$(uname)" == "Linux" ]]; then
    assert_output "/dev/shm/memo-$to_be_created_file"

    run cat "/dev/shm/memo-$to_be_created_file"
    assert_output "# test"
  else
    assert_output --regexp "^.*/tmp\.[A-Za-z0-9]+\/memo-$to_be_created_file\$"
  fi

}

@test "decrypts existing file in tmpfile" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run _make_or_edit_file "$file.gpg"
  assert_success

  if [[ "$(uname)" == "Linux" ]]; then
    assert_output "/dev/shm/memo-test.md"

    run cat "/dev/shm/memo-test.md"
    assert_output "Hello World"
  else
    assert_output --regexp "^.*/tmp\.[A-Za-z0-9]+\/memo-test\.md$"
  fi
}

@test "decrypts existing current date daily in tmpfile" {
  local date
  date="$(date +%F)"

  mkdir -p "$JOURNAL_NOTES_DIR"

  local file
  file="$JOURNAL_NOTES_DIR/$date.md"
  printf "# %s" "$date" >"$file"

  _gpg_encrypt "$file" "$file.gpg"

  run _make_or_edit_file "$file.gpg"
  assert_success
  if [[ "$(uname)" == "Linux" ]]; then
    assert_output "/dev/shm/memo-$date.md"

    run cat "/dev/shm/memo-$date.md"
    assert_output "# $date"

  else
    assert_output --regexp "^.*/tmp\.[A-Za-z0-9]+\/memo-$date\.md$"
  fi
}
