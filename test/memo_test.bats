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

@test "successfully creates a new memo with todays date as filename when it does not exist" {

  local date=
  date=$(date +%F)

  local to_be_created_file
  to_be_created_file=$JOURNAL_NOTES_DIR/"$date.md.gpg"

  run memo ""
  assert_success

  run file_exists "$to_be_created_file"
  assert_success

  run cat "$to_be_created_file"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "successfully creates a new memo with todays date as filename and header when it does not exist when MEMO_NEOVIM_INTEGRATION = true" {
  # Run in subshell to avoid collision with other tests
  (
    local MEMO_NEOVIM_INTEGRATION=true
    local EDITOR_CMD="nvim"

    local date=
    date=$(date +%F)

    local to_be_created_file
    to_be_created_file=$JOURNAL_NOTES_DIR/"$date.md.gpg"

    # Mock nvim
    # shellcheck disable=SC2329
    nvim() {
      printf "%s" "$to_be_created_file"
    }

    run memo ""
    assert_success
    assert_output "$to_be_created_file"

    run cat "$to_be_created_file"
    assert_output "# $date"
  )
}

@test "successfully edits existing file when MEMO_NEOVIM_INTEGRATION = true" {
  # Run in subshell to avoid collision with other tests
  (
    local MEMO_NEOVIM_INTEGRATION=true
    local EDITOR_CMD="nvim"

    local file
    file="$NOTES_DIR/test.md"
    printf "Hello World" >"$file"

    gpg_encrypt "$file" "$file.gpg"

    # Mock nvim
    # shellcheck disable=SC2329
    nvim() {
      printf "%s" "$file"
    }

    run memo "$file.gpg"
    assert_success

    run cat "$file.gpg"
    assert_output --partial "-----BEGIN PGP MESSAGE-----"
  )
}

@test "successfully edits existing file" {
  local file
  file="$NOTES_DIR/test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run memo "$file.gpg"
  assert_success
}

@test "successfully creates new file in notes dir ($NOTES_DIR)" {
  local file="new-file-test.md"

  run memo "$file"
  assert_success

  run cat "$NOTES_DIR/$file.gpg"
  assert_output --partial "-----BEGIN PGP MESSAGE-----"
}

@test "fails editting existing file since its not in the notes dir ($NOTES_DIR)" {
  local file
  file="test.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  run memo "$file.gpg"
  assert_failure
  assert_output "Error: File is not a valid gpg memo in the notes directory."

  # Cleanup
  rm -f "$file" "$file.gpg"
}
