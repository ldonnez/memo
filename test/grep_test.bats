#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
  rm -f "$CACHE_FILE"
}

@test "grep should successfully find and edit a note" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  # Mock fzf to return the selected line
  # shellcheck disable=SC2329
  fzf() {
    # Verify the input to fzf
    local fzf_input
    read -r -d '' fzf_input

    printf "%s" "$fzf_input"
  }

  # Mock memo_edit to verify it's called with the correct arguments
  # shellcheck disable=SC2329
  memo_edit() {
    if [[ "$1" == "$NOTES_DIR/file.md.gpg" ]]; then
      printf "memo_edit called with correct file\n"
    else
      printf "memo_edit called with wrong file\n" >&2
    fi
  }

  run grep ""

  assert_success
  assert_output "memo_edit called with correct file"
}

@test "grep should do nothing when no line is selected in fzf" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  fzf() {
    printf ""
  }

  # Mock memo_edit to verify it's called with the correct arguments
  memo_edit() {
    printf "memo_edit was called unexpectedly\n" >&2
    return 1
  }

  run grep ""

  assert_success
  refute_output "memo_edit was called unexpectedly"
}
