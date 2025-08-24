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

@test "should successfully find and edit a note" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  # Mock fzf to return the selected line
  # shellcheck disable=SC2329
  fzf() {
    local fzf_input
    read -r -d '' fzf_input

    printf "%s" "$fzf_input"
  }

  # Mock rg to return the selected line
  # shellcheck disable=SC2329
  rg() {
    local rg_input
    read -r -d '' rg_input

    printf "%s" "$rg_input"

  }

  # Mock memo to verify it's called with the correct arguments
  # shellcheck disable=SC2329
  memo() {
    if [[ "$1" == "$NOTES_DIR/file.md.gpg" ]]; then
      printf "memo called with correct file\n"
    else
      printf "memo called with wrong file\n" >&2
    fi
  }

  run memo_grep ""

  assert_success
  assert_output "memo called with correct file"
}

@test "should do nothing when no line is selected in fzf" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  printf "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  memo_cache

  fzf() {
    printf ""
  }

  rg() {
    printf ""
  }

  # Mock memo to verify it's called with the correct arguments
  memo() {
    printf "memo was called unexpectedly\n" >&2
    return 1
  }

  run memo_grep ""

  assert_success
  refute_output "memo was called unexpectedly"
}

@test "returns error if fzf and rg is not found in PATH" {

  run memo_grep ""
  assert_failure
  assert_output "Error: gpg, rg and fzf are required for memo_grep"
}
